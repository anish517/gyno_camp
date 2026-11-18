import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';
import 'package:gyno_camp/viewmodels/ocr_scan_viewmodel.dart';
import 'package:gyno_camp/views/scanner/form_scan_view.dart';

void main() {
  group('FormScanView Widget Tests', () {
    testWidgets('FormScanView renders dual-slot capture prompt with Page 1 and Page 2 cards', (WidgetTester tester) async {
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

      expect(find.text('Scan & Auto-Fill Yellow Form'), findsOneWidget);
      expect(find.text('Page 1 (Front Page)'), findsOneWidget);
      expect(find.text('Page 2 (Back Page)'), findsOneWidget);
      expect(find.text('Select Both Images at Once (Multi-Select)'), findsOneWidget);
      expect(find.text('Load Complete 2-Page Template'), findsNothing);
    });

    testWidgets('Loading 2-Page scan result renders dual-page inspection and verification tabs', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const FormScanView(),
          ),
        ),
      );
      await tester.pump();

      // Trigger 2-page scan state via viewmodel
      await container.read(ocrScanProvider.notifier).loadSample('full');
      await tester.pumpAndSettle();

      // Check inspection tabs
      expect(find.text('Page 1 (Front: Demographics)'), findsOneWidget);
      expect(find.text('Page 2 (Back: POP & Vitals)'), findsOneWidget);

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

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const FormScanView(),
          ),
        ),
      );
      await tester.pump();

      // Trigger 2-page scan state via viewmodel
      await container.read(ocrScanProvider.notifier).loadSample('full');
      await tester.pumpAndSettle();

      // Switch to Obstetric History tab
      await tester.tap(find.text('2. Obstetric History'));
      await tester.pumpAndSettle();

      // Verify full-width steppers with complete labels
      expect(find.text('Deliveries / Parity (सुत्केरी संख्या)'), findsOneWidget);
      expect(find.text('Living Children (जीवित बालबच्चा)'), findsOneWidget);
      expect(find.text('Abortions / Miscarriages (गर्भपतन)'), findsOneWidget);

      // Verify Complaints Duration and 9 Chief Clinical Complaints in Obstetric tab
      expect(find.text('Chief Clinical Complaints (प्रमुख क्लिनिकल लक्षणहरू)'), findsOneWidget);
      expect(find.text('Something hanging out / Prolapse (पाठेघर खस्ने समस्या)'), findsOneWidget);
      expect(find.text('Discharge and/or Itching (पानी बग्ने / चिलाउने)'), findsOneWidget);

      // Switch to POP Staging tab
      await tester.tap(find.text('3. POP Staging'));
      await tester.pumpAndSettle();

      // Verify Uterus Inside, Pelvic Floor Muscle, Vulva Examination
      expect(find.text('Uterus Inside:'), findsOneWidget);
      expect(find.text('Pelvic Floor Muscle (पेल्भिक मांसपेशी):'), findsOneWidget);
      expect(find.text('1. Vulva Examination (बाह्य अङ्ग / भल्भा):'), findsOneWidget);

      // Switch to Vitals & Diagnoses tab
      await tester.tap(find.text('4. Vitals & Diagnoses'));
      await tester.pumpAndSettle();

      // Verify Point-of-care lab tests (Urine test & UPT)
      expect(find.text('Urine Test (पिसाब जाँच):'), findsOneWidget);
      expect(find.text('Pregnancy Test (UPT) (गर्भ जाँच):'), findsOneWidget);

      // Verify back button to return to capture slots
      expect(find.byTooltip('Return to Document Upload Slots'), findsOneWidget);
      await tester.tap(find.byTooltip('Return to Document Upload Slots'));
      await tester.pumpAndSettle();

      // We should now be back on the dual-slot capture prompt
      expect(find.text('Scan & Auto-Fill Yellow Form'), findsOneWidget);
      expect(find.text('Page 1 (Front Page)'), findsOneWidget);
      expect(find.text('Page 2 (Back Page)'), findsOneWidget);
    });

    testWidgets('FormScanView renders Scanned Form Photos archive card with Review & Correct and Delete Photo options', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const valid1x1PngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final sampleScan = const OcrFormService().parseFormText(OcrFormService.sampleFullFormText);
      final archivedItem = OfflineScanQueueItem(
        id: 'scanarch-pat-001',
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        page1ImageBase64: valid1x1PngBase64,
        page2ImageBase64: valid1x1PngBase64,
        status: 'completed',
        reviewStatus: 'needs_review',
        committedPatientUuid: 'pat-001',
        committedPatientId: 'GC-KTM01-2026-00012',
        committedPatientName: 'Maya Tamang',
        committedVisitId: 'vis-001',
        extractedJson: jsonEncode(sampleScan.toMap()),
        createdAt: DateTime(2026, 11, 18),
        updatedAt: DateTime(2026, 11, 18),
        createdByUserId: 'usr-1',
        createdByUserName: 'Staff',
        createdByUserRole: 'DataTaker',
        deviceId: 'dev-1',
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const FormScanView(),
          ),
        ),
      );
      await tester.pump();

      container.read(ocrScanProvider.notifier).state = OcrScanState(
        offlineQueue: [archivedItem],
      );
      await tester.pumpAndSettle();

      expect(find.text('Scanned Form Photos — Review & Correction (1)'), findsOneWidget);
      expect(find.text('Maya Tamang'), findsOneWidget);
      expect(find.text('GC-KTM01-2026-00012'), findsOneWidget);
      expect(find.text('AUTO-SAVED • NEEDS REVIEW'), findsOneWidget);
      expect(find.text('Review & Correct'), findsOneWidget);

      // Tap Delete Photo icon to open granular deletion dialog
      await tester.tap(find.byTooltip('Delete Stored Scan Photo'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Stored Scan Photo?'), findsOneWidget);
      expect(
        find.text('The committed patient and clinical visit record in the database will NOT be deleted.'),
        findsOneWidget,
      );
      expect(find.text('Delete Page 1 Photo'), findsOneWidget);
      expect(find.text('Delete Page 2 Photo'), findsOneWidget);
      expect(find.text('Delete Both Photos'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Tap Review & Correct to open split-screen verification mode
      await tester.tap(find.text('Review & Correct'));
      await tester.pumpAndSettle();

      expect(
        find.text('REVIEW & CORRECTION MODE • Saving updates the existing patient & clinical visit record in-place.'),
        findsOneWidget,
      );
    });

    testWidgets('FormScanView infers Koshi province when district is Dhankuta and province is missing or mismatched', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final sampleScan = const OcrFormService()
          .parseFormText(OcrFormService.sampleFullFormText)
          .copyWith(
            demographics: {
              'firstName': 'Sita',
              'surname': 'Rai',
              'age': 41,
              'district': 'Dhankuta',
              'municipality': 'Pakhribas',
              'ward': '04',
              // Deliberately omit province or pass mismatched province
              'province': null,
            },
          );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const FormScanView(),
          ),
        ),
      );
      await tester.pump();

      container.read(ocrScanProvider.notifier).state = OcrScanState(
        page1Scan: sampleScan,
        scanResult: sampleScan,
      );
      await tester.pumpAndSettle();

      // Verify no DropdownButton assertion exception occurred and Dhankuta + Koshi are selected
      expect(tester.takeException(), isNull);
      expect(find.text('Koshi'), findsOneWidget);
      expect(find.text('Dhankuta'), findsOneWidget);
      expect(find.text('Pakhribas'), findsOneWidget);
    });
  });
}
