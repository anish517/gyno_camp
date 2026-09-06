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
    const LookupItemModel(id: 'm1', category: 'medicine', code: 'metronidazole', labelEn: 'Metronidazole 400mg', labelNe: 'मेट्रोनिडाजोल', isActive: true),
    const LookupItemModel(id: 'h1', category: 'referral_hospital', code: 'scheer', labelEn: 'Scheer Memorial Hospital', labelNe: 'शीर मेमोरियल', isActive: true),
  ];

  @override
  Future<List<LookupItemModel>> getAllItems() async => items;

  @override
  Future<List<LookupItemModel>> getItemsByCategory(String category, {bool activeOnly = false}) async {
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
  Future<bool> toggleItemStatus(String id, bool isActive, {required String userId, required String userName, required String deviceId}) async {
    final idx = items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(isActive: isActive);
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteItem(String id, {required String userId, required String userName, required String deviceId}) async {
    items.removeWhere((i) => i.id == id);
    return true;
  }

  @override
  Future<void> ensureDefaultsSeeded() async {}
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

  testWidgets('MasterConfigView renders tabs and diagnosis items', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeRepo = FakeLookupRepository();
    await tester.pumpWidget(createTestWidget(fakeRepo));
    await tester.pumpAndSettle();

    expect(find.text('Clinical Master Data & Formulary'), findsOneWidget);
    expect(find.text('Diagnoses (2)'), findsOneWidget);
    expect(find.text('Medicines (1)'), findsOneWidget);
    expect(find.text('Hospitals (1)'), findsOneWidget);

    expect(find.text('Candid Infection'), findsOneWidget);
    expect(find.text('Pelvic Inflammatory Disease'), findsOneWidget);
  });

  testWidgets('Switching tab displays medicines', (tester) async {
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
  });

  testWidgets('Search query filters diagnoses in real time', (tester) async {
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
  });
}
