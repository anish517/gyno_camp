import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/repositories/lookup_repository.dart';
import 'package:gyno_camp/viewmodels/master_lookup_viewmodel.dart';
import 'package:gyno_camp/views/admin/master_config_view.dart';

class FakeLookupRepository implements ILookupRepository {
  List<LookupItemModel> items = [
    const LookupItemModel(id: 'd1', category: 'diagnosis', code: 'candid', labelEn: 'Candid Infection', labelNe: 'कन्डिडा', isActive: true),
    const LookupItemModel(id: 'd2', category: 'diagnosis', code: 'pid', labelEn: 'Pelvic Inflammatory Disease', labelNe: 'तल्लो पेटको सुजन', isActive: true),
    const LookupItemModel(id: 'd3', category: 'diagnosis', code: 'uti', labelEn: 'Urinary Tract Infection', labelNe: 'पिसाब संक्रमण', isActive: false),
    const LookupItemModel(id: 'm1', category: 'medicine', code: 'metronidazole', labelEn: 'Metronidazole 400mg', labelNe: 'मेट्रोनिडाजोल', isActive: true),
    const LookupItemModel(id: 'h1', category: 'referral_hospital', code: 'scheer', labelEn: 'Scheer Memorial Hospital', labelNe: 'शीर मेमोरियल', isActive: true),
  ];

  @override
  Future<List<LookupItemModel>> getAllItems({String? campId, String? tenantId}) async => items;

  @override
  Future<List<LookupItemModel>> getItemsByCategory(String category, {String? campId, String? tenantId, bool activeOnly = false}) async {
    return items.where((i) => i.category == category && (!activeOnly || i.isActive)).toList();
  }

  @override
  Future<LookupItemModel> addItem(LookupItemModel item, {required String userId, required String userName, required String deviceId}) async {
    items.add(item);
    return item;
  }

  @override
  Future<LookupItemModel> updateItem(LookupItemModel item, {required String userId, required String userName, required String deviceId}) async {
    final idx = items.indexWhere((i) => i.id == item.id);
    if (idx != -1) items[idx] = item;
    return item;
  }

  @override
  Future<bool> toggleItemStatus(String id, bool isActive, {String? campId, required String userId, required String userName, required String deviceId}) async {
    final idx = items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(isActive: isActive);
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteItem(String id, {String? campId, required String userId, required String userName, required String deviceId}) async {
    if (campId != null) {
      final idx = items.indexWhere((i) => i.id == id);
      if (idx != -1 && items[idx].campId == null) {
        items[idx] = items[idx].copyWith(
          excludedCampIds: [...items[idx].excludedCampIds, campId],
        );
        return true;
      }
    }
    items.removeWhere((i) => i.id == id);
    return true;
  }

  @override
  Future<bool> restoreItemToCamp(String id, {required String campId, required String userId, required String userName, required String deviceId}) async {
    final idx = items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(
        excludedCampIds: items[idx].excludedCampIds.where((c) => c != campId).toList(),
      );
      return true;
    }
    return false;
  }

  @override
  Future<void> ensureDefaultsSeeded({String? tenantId}) async {}
}

void main() {
  Widget createTestWidget(ILookupRepository repo) {
    return ProviderScope(
      overrides: [
        lookupRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MasterConfigView(),
      ),
    );
  }

  testWidgets('MasterConfigView renders tabs, KPI cards, and diagnosis items', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    expect(find.text('Clinical Master Data & Formulary'), findsOneWidget);
    expect(find.text('Diagnoses (3)'), findsOneWidget);
    expect(find.text('Medicines (1)'), findsOneWidget);
    expect(find.text('Referral Hospitals (1)'), findsOneWidget);

    // KPI cards
    expect(find.text('Active Diagnoses'), findsOneWidget);
    expect(find.text('Disabled / Inactive'), findsOneWidget);
    expect(find.text('Total Diagnoses'), findsOneWidget);

    expect(find.text('Candid Infection'), findsOneWidget);
    expect(find.text('Pelvic Inflammatory Disease'), findsOneWidget);
    expect(find.text('Urinary Tract Infection'), findsOneWidget);
  });

  testWidgets('MasterConfigView renders cleanly on mobile viewport without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    expect(find.text('Master Data & Formulary'), findsOneWidget);
    expect(find.text('Active Diagnoses'), findsOneWidget);
    expect(find.text('Candid Infection'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('Switching tab displays medicines and updates KPI cards', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap Medicines tab
    await tester.tap(find.text('Medicines (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Metronidazole 400mg'), findsOneWidget);
    expect(find.text('Active Medicines'), findsOneWidget);
    expect(find.text('Total Medicines'), findsOneWidget);
  });

  testWidgets('Switching to Referral Hospitals tab displays partner hospital and contextual helper', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap Referral Hospitals tab
    await tester.tap(find.text('Referral Hospitals (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Scheer Memorial Hospital'), findsOneWidget);
    expect(find.textContaining('Surgical Referral Centers: Configure tertiary surgical partner hospitals'), findsOneWidget);
    expect(find.text('CODE: SCHEER'), findsOneWidget);
    expect(find.text('Active Referral Hospitals'), findsOneWidget);
  });

  testWidgets('Search query filters diagnoses in real time and clear button resets', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'candid');
    await tester.pumpAndSettle();

    expect(find.text('Candid Infection'), findsOneWidget);
    expect(find.text('Pelvic Inflammatory Disease'), findsNothing);

    // Tap clear button
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.text('Candid Infection'), findsOneWidget);
    expect(find.text('Pelvic Inflammatory Disease'), findsOneWidget);
  });

  testWidgets('Status filter chips filter active, inactive, and all items', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // All Items shows Candid, PID, and UTI
    expect(find.text('Candid Infection'), findsOneWidget);
    expect(find.text('Urinary Tract Infection'), findsOneWidget);

    // Tap Active Only chip
    await tester.tap(find.text('Active Only'));
    await tester.pumpAndSettle();

    expect(find.text('Candid Infection'), findsOneWidget);
    expect(find.text('Pelvic Inflammatory Disease'), findsOneWidget);
    expect(find.text('Urinary Tract Infection'), findsNothing);

    // Tap Disabled chip
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();

    expect(find.text('Candid Infection'), findsNothing);
    expect(find.text('Urinary Tract Infection'), findsOneWidget);
  });

  testWidgets('Adding a new item through dialog saves and displays in list', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap Add Diagnosis button in AppBar
    await tester.tap(find.text('Add Diagnosis'));
    await tester.pumpAndSettle();

    expect(find.text('Add New Diagnosis'), findsOneWidget);
    expect(find.text('English Name / Term *'), findsOneWidget);

    // Fill form
    await tester.enterText(find.widgetWithText(TextField, 'English Name / Term *'), 'Bacterial Vaginosis');
    await tester.enterText(find.widgetWithText(TextField, 'Nepali Translation (नेपाली नाम)'), 'ब्याक्टेरियल संक्रमण');
    await tester.pumpAndSettle();

    // Save
    await tester.tap(find.text('Add Item'));
    await tester.pumpAndSettle();

    expect(find.text('Bacterial Vaginosis'), findsOneWidget);
    expect(fakeRepo.items.any((i) => i.labelEn == 'Bacterial Vaginosis'), isTrue);
  });

  testWidgets('Deactivating item via delete dialog updates item status', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap delete on Candid Infection (first delete icon)
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('Delete Master Item?'), findsOneWidget);
    expect(find.text('Deactivate Instead'), findsOneWidget);

    // Tap Deactivate Instead
    await tester.tap(find.text('Deactivate Instead'));
    await tester.pumpAndSettle();

    expect(fakeRepo.items.firstWhere((i) => i.labelEn == 'Candid Infection').isActive, isFalse);
  });

  testWidgets('Permanently deleting item removes it from repository', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    // Tap delete on Candid Infection
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    // Tap Delete Permanently
    await tester.tap(find.text('Delete Permanently'));
    await tester.pumpAndSettle();

    expect(fakeRepo.items.any((i) => i.labelEn == 'Candid Infection'), isFalse);
  });

  testWidgets('Scoped to camp: deleting a global item shows Remove from Selected Camp dialog without deleting globally', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lookupRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MasterConfigView(initialCampId: 'camp-testing-01'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap delete on Candid Infection (first delete icon)
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('Remove from Selected Camp?'), findsOneWidget);
    expect(find.text('Remove from Camp'), findsOneWidget);
    expect(find.textContaining('This will ONLY remove it for this specific camp'), findsOneWidget);

    // Tap Remove from Camp
    await tester.tap(find.text('Remove from Camp'));
    await tester.pumpAndSettle();

    // Verify it is NOT deleted from fakeRepo.items, but its excludedCampIds now includes 'camp-testing-01'
    final candid = fakeRepo.items.firstWhere((i) => i.labelEn == 'Candid Infection');
    expect(candid.excludedCampIds, contains('camp-testing-01'));
  });
}
