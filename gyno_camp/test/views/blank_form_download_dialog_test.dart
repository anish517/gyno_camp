import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/views/shared/blank_form_download_dialog.dart';
import 'package:material_ui/material_ui.dart';

class _FakePatientRepository extends Fake implements IPatientRepository {
  final List<PatientModel> seededPatients;

  _FakePatientRepository({this.seededPatients = const []});

  @override
  Future<List<PatientModel>> getPatientsByCamp([
    String? campId,
    List<String>? allowedCampIds,
  ]) async {
    return seededPatients;
  }
}

CampModel _buildTestCamp() {
  return CampModel(
    id: 'camp-bulk-01',
    campCode: '111',
    name: 'Budhanilkantha Women Health Camp',
    province: 'Bagmati',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    ward: '04',
    venue: 'Health Post',
    startDate: DateTime(2026, 11, 25),
    endDate: DateTime(2026, 11, 27),
    doctorNames: const ['Dr. Anish Tiwari (NMC: 12345)'],
    createdAt: DateTime(2026, 11, 20),
  );
}

List<PatientModel> _buildSeededPatients() {
  return [
    PatientModel(
      id: 'pt-1',
      patientId: '00120',
      campId: 'camp-bulk-01',
      campCode: '111',
      intakeDate: DateTime(2026, 11, 25),
      firstName: 'Sita',
      surname: 'Shrestha',
      age: 35,
      maritalStatus: 'married',
      spouseOrFatherName: 'Ram Shrestha',
      mobile: '9841000001',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '04',
      createdByUserId: 'usr-1',
      createdByDeviceId: 'dev-1',
      createdAt: DateTime(2026, 11, 25),
      updatedAt: DateTime(2026, 11, 25),
    ),
  ];
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required Size size,
  List<PatientModel> seededPatients = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  final camp = _buildTestCamp();
  final fakePatientRepo = _FakePatientRepository(seededPatients: seededPatients);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        patientRepositoryProvider.overrideWithValue(fakePatientRepo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: BlankFormDownloadDialog(camp: camp),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('BlankFormDownloadDialog Bulk Pre-Numbered Controls', () {
    testWidgets(
      'renders cleanly with zero overflow on desktop (1280x900) and narrow mobile (360x800)',
      (WidgetTester tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Desktop viewport
        await _pumpDialog(
          tester,
          size: const Size(1280, 900),
          seededPatients: _buildSeededPatients(),
        );
        expect(tester.takeException(), isNull);

        final toggleFinder = find.byKey(const Key('enable_pre_numbered_tokens_switch'));
        await tester.ensureVisible(toggleFinder);
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Next available sequence after 00120 is 00121 (default count 50 -> 00121 -> 00170)
        expect(find.text('00121 → 00170'), findsOneWidget);
        expect(find.byKey(const Key('start_chip_next_free')), findsOneWidget);
        expect(find.byKey(const Key('bulk_pack_next_100')), findsOneWidget);

        // 2. Narrow mobile viewport (360x800)
        await _pumpDialog(
          tester,
          size: const Size(360, 800),
          seededPatients: _buildSeededPatients(),
        );
        expect(tester.takeException(), isNull);

        final mobileToggle = find.byKey(const Key('enable_pre_numbered_tokens_switch'));
        await tester.ensureVisible(mobileToggle);
        await tester.tap(mobileToggle);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '1-tap Bulk Packs and large Quantity chips update range & multi-volume split without typing',
      (WidgetTester tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpDialog(
          tester,
          size: const Size(1280, 900),
          seededPatients: _buildSeededPatients(),
        );

        final toggleFinder = find.byKey(const Key('enable_pre_numbered_tokens_switch'));
        await tester.ensureVisible(toggleFinder);
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        // Tap 1-500 Bulk Pack -> sets start=1, count=500, auto-enables 2 PDF volumes
        final pack1To500 = find.byKey(const Key('bulk_pack_1_500'));
        await tester.ensureVisible(pack1To500);
        await tester.tap(pack1To500);
        await tester.pumpAndSettle();

        expect(find.text('00001 → 00500'), findsOneWidget);
        expect(find.text('Download 500 Pre-Numbered Forms (2 PDFs)'), findsOneWidget);

        // Tap 501-1000 Bulk Pack -> sets start=501, count=500
        final pack501To1000 = find.byKey(const Key('bulk_pack_501_1000'));
        await tester.ensureVisible(pack501To1000);
        await tester.tap(pack501To1000);
        await tester.pumpAndSettle();

        expect(find.text('00501 → 01000'), findsOneWidget);

        // Tap Quick Quantity 1000 -> sets count=1000 (00501 -> 01500, 4 PDFs)
        final qty1000 = find.byKey(const Key('qty_chip_1000'));
        await tester.ensureVisible(qty1000);
        await tester.tap(qty1000);
        await tester.pumpAndSettle();

        expect(find.text('00501 → 01500'), findsOneWidget);
        expect(find.text('Download 1000 Pre-Numbered Forms (4 PDFs)'), findsOneWidget);

        // Toggle off multi-volume split -> single combined file label, while switch label still shows true volume count (4 files)
        final splitSwitch = find.byKey(const Key('split_large_batch_volumes_switch'));
        await tester.ensureVisible(splitSwitch);
        await tester.tap(splitSwitch);
        await tester.pumpAndSettle();

        expect(find.text('Download 1000 Pre-Numbered Forms'), findsOneWidget);
        expect(
          find.text('Split into print-ready PDF volumes (4 files • 250 forms/PDF)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Prev/Next block buttons and Start presets step ranges cleanly without keyboard input',
      (WidgetTester tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpDialog(
          tester,
          size: const Size(1280, 900),
          seededPatients: _buildSeededPatients(),
        );

        final toggleFinder = find.byKey(const Key('enable_pre_numbered_tokens_switch'));
        await tester.ensureVisible(toggleFinder);
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        // Select 1-250 pack
        final pack1To250 = find.byKey(const Key('bulk_pack_1_250'));
        await tester.ensureVisible(pack1To250);
        await tester.tap(pack1To250);
        await tester.pumpAndSettle();
        expect(find.text('00001 → 00250'), findsOneWidget);

        // Step Next -> 00251 -> 00500 -> Step Next -> 00501 -> 00750
        final nextBtn = find.byKey(const Key('token_range_next_block_btn'));
        await tester.ensureVisible(nextBtn);
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();
        expect(find.text('00251 → 00500'), findsOneWidget);

        await tester.tap(nextBtn);
        await tester.pumpAndSettle();
        expect(find.text('00501 → 00750'), findsOneWidget);

        // Step Prev -> 00251 -> 00500
        final prevBtn = find.byKey(const Key('token_range_prev_block_btn'));
        await tester.tap(prevBtn);
        await tester.pumpAndSettle();
        expect(find.text('00251 → 00500'), findsOneWidget);

        // Jump to Start preset 1001 -> 01001 -> 01250
        final start1001 = find.byKey(const Key('start_chip_1001'));
        await tester.ensureVisible(start1001);
        await tester.tap(start1001);
        await tester.pumpAndSettle();
        expect(find.text('01001 → 01250'), findsOneWidget);

        // Restore Next Free (#00121) -> 00121 -> 00370
        final nextFreeChip = find.byKey(const Key('start_chip_next_free'));
        await tester.ensureVisible(nextFreeChip);
        await tester.tap(nextFreeChip);
        await tester.pumpAndSettle();
        expect(find.text('00121 → 00370'), findsOneWidget);
      },
    );

    testWidgets(
      'typing > 500 never resets to 50 and values > 5000 clamp cleanly with notice',
      (WidgetTester tester) async {
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpDialog(
          tester,
          size: const Size(1280, 900),
          seededPatients: _buildSeededPatients(),
        );

        final toggleFinder = find.byKey(const Key('enable_pre_numbered_tokens_switch'));
        await tester.ensureVisible(toggleFinder);
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        final countInput = find.byKey(const Key('pre_numbered_count_input'));
        await tester.ensureVisible(countInput);
        await tester.enterText(countInput, '1000');
        await tester.pumpAndSettle();

        // Starts at 121, count 1000 -> 00121 -> 01120 (NOT reset to 50!)
        expect(find.text('00121 → 01120'), findsOneWidget);
        expect(find.text('Download 1000 Pre-Numbered Forms (4 PDFs)'), findsOneWidget);

        // Enter 7500 -> clamped to 5000 with clear warning
        await tester.enterText(countInput, '7500');
        await tester.pumpAndSettle();

        expect(find.text('00121 → 05120'), findsOneWidget);
        expect(
          find.textContaining('Max 5,000 forms per batch'),
          findsOneWidget,
        );
        expect(find.text('Download 5000 Pre-Numbered Forms (20 PDFs)'), findsOneWidget);
      },
    );
  });
}
