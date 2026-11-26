import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
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

      expect(find.text('Scan & Auto-Fill Yellow Form'), findsNothing);
      expect(find.textContaining('FILLED IN BLOCK LETTERS'), findsNothing);
      expect(find.text('Clinical Quality Standards & Digitization Protocols'), findsNothing);
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
      expect(find.text('Scan & Auto-Fill Yellow Form'), findsNothing);
      expect(find.textContaining('FILLED IN BLOCK LETTERS'), findsNothing);
      expect(find.text('Clinical Quality Standards & Digitization Protocols'), findsNothing);
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

    testWidgets('Full-screen dual-page form preview dialog does not overflow on 360px mobile screen', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const valid1x1PngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final pngBytes = base64Decode(valid1x1PngBase64);
      final sampleScan = const OcrFormService()
          .parseFormText(OcrFormService.sampleFullFormText);

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
        page2Scan: sampleScan,
        scanResult: sampleScan,
        page1ImageBytes: pngBytes,
        page2ImageBytes: pngBytes,
      );
      await tester.pumpAndSettle();

      // Tap Preview button on mobile verification header
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Page 1 (Front)'), findsOneWidget);
      expect(find.text('Page 2 (Back)'), findsOneWidget);
    });

    testWidgets('FormScanView targets staff assigned open camp (2222) instead of newer unassigned global activeCamp (122)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final assignedCamp = CampModel(
        id: 'camp-2222',
        campCode: '2222',
        name: 'Women for Women Sodesi',
        district: 'Bhojpur',
        municipality: 'Aamchok',
        ward: '05',
        venue: 'Chitwan Medical College',
        startDate: DateTime(2026, 11, 17),
        endDate: DateTime(2026, 12, 14),
        status: CampStatus.open,
        assignedStaffIds: const ['usr-anish'],
        doctorNames: const ['Dr. Anish Tiwari'],
        createdAt: DateTime(2026, 11, 17),
      );
      final newerUnassignedCamp = CampModel(
        id: 'camp-122',
        campCode: '122',
        name: 'new official testing',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        ward: '01',
        venue: 'Health Post',
        startDate: DateTime(2026, 11, 19),
        endDate: DateTime(2026, 11, 21),
        status: CampStatus.open,
        assignedStaffIds: const [],
        doctorNames: const ['Dr. Wrong Camp'],
        createdAt: DateTime(2026, 11, 19),
      );
      final staffUser = UserModel(
        id: 'usr-anish',
        name: 'Anish Tiwari',
        email: 'anish@gynocamp.org',
        phone: '9841000000',
        role: UserRole.dataTaker,
        assignedCampIds: const ['camp-2222'],
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(authStateProvider.notifier).state = AuthState(
        currentUser: staffUser,
      );
      container.read(campStateProvider.notifier).state = CampState(
        camps: [newerUnassignedCamp, assignedCamp],
        activeCamp: newerUnassignedCamp, // Global activeCamp is the newer camp 122!
      );

      expect(container.read(userActiveCampProvider)?.id, 'camp-2222');

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

      // AppBar MUST display the staff-assigned camp 2222, NOT 122
      expect(find.text('Camp: 2222 • Women for Women Sodesi'), findsOneWidget);
      expect(find.textContaining('new official testing'), findsNothing);
    });

    testWidgets(
      'Review & Verify Complete Dual-Page Intake button appears immediately below Save Offline Scan and above Scanned Form Photos archive',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const valid1x1PngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
        final pngBytes = base64Decode(valid1x1PngBase64);
        final sampleScan = const OcrFormService()
            .parseFormText(OcrFormService.sampleFullFormText);

        final archivedItems = List.generate(
          25,
          (i) => OfflineScanQueueItem(
            id: 'scan-${i + 1}',
            campId: 'camp-2222',
            campCode: '2222',
            page1ImageBase64: valid1x1PngBase64,
            page2ImageBase64: valid1x1PngBase64,
            status: 'completed',
            committedPatientUuid: 'uuid-${i + 1}',
            committedPatientId: 'GC-2222-2026-${(i + 1).toString().padLeft(5, '0')}',
            committedPatientName: 'Patient Sample ${i + 1}',
            reviewStatus: i % 3 == 0 ? 'needs_review' : 'reviewed',
            createdAt: DateTime(2026, 11, 19, 10, i),
            updatedAt: DateTime(2026, 11, 19, 10, i),
            createdByUserId: 'usr-1',
            createdByUserName: 'Staff',
            createdByUserRole: 'DataTaker',
            deviceId: 'dev-1',
          ),
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
          page2Scan: sampleScan,
          page1ImageBytes: pngBytes,
          page2ImageBytes: pngBytes,
          offlineQueue: archivedItems,
        );
        await tester.pumpAndSettle();

        final saveOfflineBtn = find.text(
          'Save Scan to Local Storage (Sync After Internet Connection)',
        );
        final reviewDualBtn = find.text(
          'Review & Verify Complete Dual-Page Intake (दुवै पाना रुजु गर्नुहोस्)',
        );
        final scanBothBtn = find.text('Scan Both Pages (Edge Detect & OMR)');
        final archiveHeader = find.text(
          'Scanned Form Photos — Review & Correction (25)',
        );

        expect(saveOfflineBtn, findsOneWidget);
        expect(reviewDualBtn, findsOneWidget);
        expect(scanBothBtn, findsOneWidget);
        expect(archiveHeader, findsOneWidget);

        // Verify exact vertical order:
        // Save Offline Scan -> Review & Verify Dual-Page -> Scan Both Pages -> Scanned Form Photos Archive
        final saveY = tester.getTopLeft(saveOfflineBtn).dy;
        final reviewY = tester.getTopLeft(reviewDualBtn).dy;
        final scanBothY = tester.getTopLeft(scanBothBtn).dy;
        final archiveY = tester.getTopLeft(archiveHeader).dy;

        expect(saveY, lessThan(reviewY));
        expect(reviewY, lessThan(scanBothY));
        expect(scanBothY, lessThan(archiveY));

        // Verify pagination caps initial archive rendering at 10 items
        expect(find.text('Showing 10 of 25 scanned forms'), findsOneWidget);
        expect(find.text('Patient Sample 1'), findsOneWidget);
        expect(find.text('Patient Sample 10'), findsOneWidget);
        expect(find.text('Patient Sample 15'), findsNothing);

        // Load More reveals the remaining items
        final loadMoreBtn = find.byKey(const ValueKey('archive_load_more_btn'));
        await tester.ensureVisible(loadMoreBtn);
        await tester.tap(loadMoreBtn);
        await tester.pumpAndSettle();

        expect(find.text('Showing 25 of 25 scanned forms'), findsOneWidget);
        expect(find.text('Patient Sample 25'), findsOneWidget);

        // Search filters archive down cleanly by patient name/token
        final searchField = find.byKey(const ValueKey('archive_search_field'));
        await tester.ensureVisible(searchField);
        await tester.enterText(searchField, 'Patient Sample 23');
        await tester.pumpAndSettle();

        expect(find.text('GC-2222-2026-00023'), findsOneWidget);
        expect(find.text('Patient Sample 1'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'FormScanView capture layout with Save Offline, Review Dual-Page, and paginated archive has zero overflow on 360px mobile screen',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const valid1x1PngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
        final pngBytes = base64Decode(valid1x1PngBase64);
        final sampleScan = const OcrFormService()
            .parseFormText(OcrFormService.sampleFullFormText);

        final archivedItems = List.generate(
          12,
          (i) => OfflineScanQueueItem(
            id: 'mob-scan-${i + 1}',
            campId: 'camp-2222',
            campCode: '2222',
            page1ImageBase64: valid1x1PngBase64,
            status: 'completed',
            committedPatientUuid: 'mob-uuid-${i + 1}',
            committedPatientId: 'GC-2222-2026-${(i + 1).toString().padLeft(5, '0')}',
            committedPatientName: 'Mobile Patient ${i + 1}',
            reviewStatus: i == 0 ? 'needs_review' : 'reviewed',
            createdAt: DateTime(2026, 11, 19, 10, i),
            updatedAt: DateTime(2026, 11, 19, 10, i),
            createdByUserId: 'usr-1',
            createdByUserName: 'Staff',
            createdByUserRole: 'DataTaker',
            deviceId: 'dev-1',
          ),
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
          page2Scan: sampleScan,
          page1ImageBytes: pngBytes,
          page2ImageBytes: pngBytes,
          offlineQueue: archivedItems,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Showing 10 of 12 scanned forms'), findsOneWidget);
      },
    );

    testWidgets(
      'AppBar back button steps back from Review & Correction Mode to clean Scan & Auto-Fill screen first, then returns to Dashboard on second press',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const valid1x1PngBase64 =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
        final sampleScan = const OcrFormService()
            .parseFormText(OcrFormService.sampleFullFormText);
        final archivedItem = OfflineScanQueueItem(
          id: 'scanarch-back-001',
          campId: 'camp-1234',
          campCode: '1234',
          page1ImageBase64: valid1x1PngBase64,
          page2ImageBase64: valid1x1PngBase64,
          status: 'completed',
          reviewStatus: 'reviewed',
          committedPatientUuid: 'pat-back-001',
          committedPatientId: 'GC-0007-2026-0012',
          committedPatientName: 'KAMALA RAI',
          committedVisitId: 'vis-back-001',
          extractedJson: jsonEncode(sampleScan.toMap()),
          createdAt: DateTime(2026, 11, 19),
          updatedAt: DateTime(2026, 11, 19),
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
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => const FormScanView(),
                          ),
                        );
                      },
                      child: const Text('Dashboard Launch Scanner'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open FormScanView from Dashboard
        await tester.tap(find.text('Dashboard Launch Scanner'));
        await tester.pumpAndSettle();

        // Populate archived scan photo and open Review & Correction Mode
        container.read(ocrScanProvider.notifier).state = OcrScanState(
          offlineQueue: [archivedItem],
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Review & Correct'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'REVIEW & CORRECTION MODE • Saving updates the existing patient & clinical visit record in-place.',
          ),
          findsOneWidget,
        );

        // 1st tap on top-left AppBar back arrow must return to Scan & Auto-Fill
        // (NOT pop straight to Dashboard) and clear review slots cleanly.
        await tester.tap(find.byKey(const ValueKey('form_scan_appbar_back_btn')));
        await tester.pumpAndSettle();

        expect(find.text('Page 1 (Front Page)'), findsOneWidget);
        expect(find.text('Dashboard Launch Scanner'), findsNothing);
        expect(find.text('Slot Empty'), findsNWidgets(2));
        expect(container.read(ocrScanProvider).isReviewingCommittedScan, isFalse);

        // 2nd tap on top-left AppBar back arrow now returns to Dashboard.
        await tester.tap(find.byKey(const ValueKey('form_scan_appbar_back_btn')));
        await tester.pumpAndSettle();

        expect(find.text('Dashboard Launch Scanner'), findsOneWidget);
      },
    );

    testWidgets(
      'FormScanView hides AI and cloud vendor branding across capture, scanning, offline, and verification states',
      (WidgetTester tester) async {
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

        void expectNoVendorBranding() {
          expect(find.textContaining('Gemini', findRichText: true), findsNothing);
          expect(find.textContaining('GEMINI', findRichText: true), findsNothing);
          expect(find.textContaining('Google', findRichText: true), findsNothing);
          expect(find.textContaining('Powered by', findRichText: true), findsNothing);
          expect(find.textContaining('Cloud OCR', findRichText: true), findsNothing);
          expect(find.textContaining('cloud OCR', findRichText: true), findsNothing);
        }

        // 1. Initial capture prompt
        expect(find.text('Page 1 (Front Page)'), findsOneWidget);
        expectNoVendorBranding();

        // 2. Active scanning / processing overlay
        container.read(ocrScanProvider.notifier).state = const OcrScanState(
          isProcessing: true,
        );
        await tester.pump();
        expect(find.text('Scanning & Digitizing Yellow Form...'), findsOneWidget);
        expectNoVendorBranding();

        // 3. Offline storage prompt state
        final dummyPng = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        );
        container.read(ocrScanProvider.notifier).state = OcrScanState(
          isProcessing: false,
          isOfflineModeDetected: true,
          page1ImageBytes: dummyPng,
        );
        await tester.pump();
        expectNoVendorBranding();

        // 4. Dual-page verification state
        await container.read(ocrScanProvider.notifier).loadSample('full');
        await tester.pumpAndSettle();
        expect(find.textContaining('Form Digitization:'), findsOneWidget);
        expectNoVendorBranding();
      },
    );

    testWidgets(
      'Blank/unfilled scan displays Not Recorded (—) and unselected chips instead of Stage 0 / Yes / 3 defaults, and guards empty required fields on commit',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final activeCamp = CampModel(
          id: 'camp-dhn-01',
          campCode: 'DHN01',
          name: 'Dhankuta Health Camp',
          province: 'Koshi',
          district: 'Dhankuta',
          municipality: 'Pakhribas',
          ward: '04',
          venue: 'Pakhribas Health Post',
          startDate: DateTime(2026, 11, 20),
          endDate: DateTime(2026, 11, 25),
          status: CampStatus.open,
          createdAt: DateTime(2026, 11, 20),
        );

        final blankScan = OcrScanResultModel(
          pageNumber: 1,
          isDualPage: true,
          rawText: 'Blank form',
          demographics: const {},
          obstetrics: const {},
          popStaging: const {},
          vitals: const {},
          diagnoses: const [],
          medications: const [],
          fieldConfidences: const {},
          overallConfidence: 0.0,
          scannedAt: DateTime(2026, 11, 25),
        );

        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(campStateProvider.notifier).state = CampState(
          camps: [activeCamp],
          activeCamp: activeCamp,
        );
        container.read(ocrScanProvider.notifier).state = OcrScanState(
          page1Scan: blankScan,
          page2Scan: blankScan,
          scanResult: blankScan,
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const FormScanView(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tab 1: Active camp location pre-filled; Marital Status is Not Recorded (—); Consents unchecked
        expect(find.text('Koshi'), findsOneWidget);
        expect(find.text('Dhankuta'), findsOneWidget);
        expect(find.text('Pakhribas'), findsOneWidget);
        expect(find.text('Not Recorded (—)'), findsOneWidget);

        final consentTiles = tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .toList();
        expect(consentTiles.length, greaterThanOrEqualTo(2));
        expect(consentTiles[0].value, isFalse);
        expect(consentTiles[1].value, isFalse);

        // Attempting to commit with empty First Name / Surname / Age shows validation SnackBar
        await tester.tap(
          find.text('Verify & Commit to Camp Database (दर्ता सम्पन्न गर्नुहोस्)'),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Required demographics missing: First Name, Surname, Age'),
          findsOneWidget,
        );

        // Tab 2: Obstetrics steppers show '—' instead of 3, 3, 0
        await tester.tap(find.text('2. Obstetric History'));
        await tester.pumpAndSettle();
        expect(find.text('—'), findsNWidgets(3));

        // Tab 3: POP Staging dropdowns show 'Not Recorded (—)' instead of Stage 0, and Uterus Inside Yes/No are both unselected
        await tester.tap(find.text('3. POP Staging'));
        await tester.pumpAndSettle();
        expect(find.text('Not Recorded (—)'), findsNWidgets(3));

        final yesChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Yes'),
        );
        final noChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'No'),
        );
        expect(yesChip.selected, isFalse);
        expect(noChip.selected, isFalse);

        // Tab 4: Urine Test Normal and Pregnancy Test Negative are unselected when null
        await tester.tap(find.text('4. Vitals & Diagnoses'));
        await tester.pumpAndSettle();
        final urineNormalChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Normal (सामान्य)'),
        );
        final pregNegChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Negative (नेगेटिभ)'),
        );
        expect(urineNormalChip.selected, isFalse);
        expect(pregNegChip.selected, isFalse);
      },
    );
  });
}
