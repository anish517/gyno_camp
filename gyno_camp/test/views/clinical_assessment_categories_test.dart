import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/constants/clinical_constants.dart';
import 'package:gyno_camp/core/services/nepali_localization_service.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';

void main() {
  group('Clinical Assessment Dynamic Category & Label Tests', () {
    test('Dynamic categories extracted properly for custom camp diagnoses', () {
      final activeDiagnoses = [
        const LookupItemModel(
          id: 'd1',
          category: 'diagnosis',
          subCategory: 'Menstrual Disorders',
          code: 'abnormal_uterine_bleeding',
          labelEn: 'Abnormal Uterine Bleeding',
          labelNe: 'असामान्य पाठेघर रक्तस्राव',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'd2',
          category: 'diagnosis',
          subCategory: 'Infection',
          code: 'cervicitis',
          labelEn: 'Cervicitis',
          labelNe: 'पाठेघरको मुखको सूजन',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'd3',
          category: 'diagnosis',
          subCategory: 'Infection',
          code: 'pelvic_inflammatory_disease',
          labelEn: 'Pelvic Inflammatory Disease',
          labelNe: 'श्रोणी सूजन रोग',
          isActive: true,
        ),
      ];

      final Map<String, String> itemToCategory = {};
      final List<String> dynamicCategories = [];

      for (final d in activeDiagnoses) {
        final cat = (d.subCategory != null && d.subCategory!.trim().isNotEmpty)
            ? d.subCategory!.trim()
            : (ClinicalConstants.diagnosisCategoryMap[d.labelEn.toLowerCase()] ?? 'General / Other');
        itemToCategory[d.labelEn] = cat;
        if (!dynamicCategories.contains(cat)) {
          dynamicCategories.add(cat);
        }
      }

      expect(dynamicCategories, contains('Menstrual Disorders'));
      expect(dynamicCategories, contains('Infection'));
      expect(dynamicCategories.length, equals(2));
      expect(itemToCategory['Abnormal Uterine Bleeding'], equals('Menstrual Disorders'));
      expect(itemToCategory['Cervicitis'], equals('Infection'));
      expect(itemToCategory['Pelvic Inflammatory Disease'], equals('Infection'));
    });

    test('Bilingual diagnosis label formats cleanly and avoids duplicate English text', () {
      final activeDiagnoses = [
        const LookupItemModel(
          id: 'd1',
          category: 'diagnosis',
          subCategory: 'Menstrual Disorders',
          code: 'abnormal_uterine_bleeding',
          labelEn: 'Abnormal Uterine Bleeding',
          labelNe: 'असामान्य पाठेघर रक्तस्राव',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'd2',
          category: 'diagnosis',
          subCategory: 'Custom',
          code: 'custom_diag',
          labelEn: 'Custom Condition',
          labelNe: '',
          isActive: true,
        ),
      ];

      String getDiagnosisDisplayLabel(String diag) {
        final masterItem = activeDiagnoses.cast<LookupItemModel?>().firstWhere(
          (d) => d != null && d.labelEn.toLowerCase() == diag.toLowerCase(),
          orElse: () => null,
        );
        final labelNe = (masterItem != null && masterItem.labelNe.isNotEmpty && masterItem.labelNe.toLowerCase() != masterItem.labelEn.toLowerCase())
            ? masterItem.labelNe
            : NepaliLocalizationService.translate(diag);
        return (labelNe.isNotEmpty && labelNe.toLowerCase() != diag.toLowerCase())
            ? '$labelNe ($diag)'
            : diag;
      }

      // Has Nepali label from master lookup
      expect(
        getDiagnosisDisplayLabel('Abnormal Uterine Bleeding'),
        equals('असामान्य पाठेघर रक्तस्राव (Abnormal Uterine Bleeding)'),
      );

      // Has no Nepali label and no dictionary translation -> outputs clean English, NOT duplicated
      expect(
        getDiagnosisDisplayLabel('Custom Condition'),
        equals('Custom Condition'),
      );
    });

    test('Dynamic categories extracted properly for custom camp medicines', () {
      final activeMedicines = [
        const LookupItemModel(
          id: 'm1',
          category: 'medicine',
          subCategory: 'Antibiotics & Antifungals',
          code: 'azithromycin_500',
          labelEn: 'Azithromycin 500 mg Tablet',
          labelNe: 'एजिथ्रोमाइसिन ५०० मि.ग्रा.',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'm2',
          category: 'medicine',
          subCategory: 'Vitamins & Supplements',
          code: 'calcium_vit_d3',
          labelEn: 'Calcium + Vitamin D3 Tablet',
          labelNe: 'क्याल्सियम + भिटामिन डी३',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'm3',
          category: 'medicine',
          subCategory: 'Pain & Fever (Analgesics)',
          code: 'paracetamol_500',
          labelEn: 'Paracetamol 500 mg Tablet',
          labelNe: 'प्यारा सिटामोल ५०० मि.ग्रा.',
          isActive: true,
        ),
      ];

      final Map<String, String> medToCategory = {};
      final List<String> dynamicMedCategories = [];

      for (final m in activeMedicines) {
        final cat = (m.subCategory != null && m.subCategory!.trim().isNotEmpty)
            ? m.subCategory!.trim()
            : (ClinicalConstants.medicationCategoryMap[m.labelEn.toLowerCase()] ?? 'Other / Custom');
        medToCategory[m.labelEn] = cat;
        if (!dynamicMedCategories.contains(cat)) {
          dynamicMedCategories.add(cat);
        }
      }

      expect(dynamicMedCategories, contains('Antibiotics & Antifungals'));
      expect(dynamicMedCategories, contains('Vitamins & Supplements'));
      expect(dynamicMedCategories, contains('Pain & Fever (Analgesics)'));
      expect(dynamicMedCategories.length, equals(3));
    });

    test('Chief complaints resolution does not append standard baseline complaints when active master complaints exist', () {
      final activeMasterComplaints = [
        const LookupItemModel(
          id: 'c1',
          category: 'chief_complaint',
          code: 'cc_vaginal_discharge',
          labelEn: 'Excessive vaginal discharge',
          labelNe: 'योनिबाट धेरै पानी बग्ने',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'c2',
          category: 'chief_complaint',
          code: 'heaviness_or_bulge_in_vagina',
          labelEn: 'Heaviness or bulge in vagina',
          labelNe: 'योनिमा भारीपन वा गाँठो देखिने',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'c3',
          category: 'chief_complaint',
          code: 'cc_heavy_irregular_periods',
          labelEn: 'Heavy or irregular periods',
          labelNe: 'धेरै वा अनियमित महिनावारी',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'c4',
          category: 'chief_complaint',
          code: 'cc_lower_abdominal_pain',
          labelEn: 'Lower abdominal pain',
          labelNe: 'तल्लो पेट दुख्ने',
          isActive: true,
        ),
      ];

      final standardComplaints = [
        {'key': 'prolapse', 'title': 'Something hanging out'},
        {'key': 'discharge', 'title': 'Discharge / Itching'},
        {'key': 'urine', 'title': 'Problems passing urine'},
        {'key': 'stool', 'title': 'Problems passing stool'},
        {'key': 'menstrual', 'title': 'Menstrual problem'},
        {'key': 'infertility', 'title': 'Infertility'},
        {'key': 'pain', 'title': 'Pelvic / Back Pain'},
      ];

      final List<Map<String, dynamic>> resolvedComplaints = [];

      if (activeMasterComplaints.isNotEmpty) {
        for (final masterItem in activeMasterComplaints) {
          final code = masterItem.code.toLowerCase().trim();
          resolvedComplaints.add({
            'key': code,
            'title': masterItem.labelEn,
          });
        }
      } else {
        for (final std in standardComplaints) {
          resolvedComplaints.add({
            'key': std['key']!,
            'title': std['title']!,
          });
        }
      }

      // Exactly the 4 configured complaints are present
      expect(resolvedComplaints.length, equals(4));
      expect(resolvedComplaints.map((c) => c['key']), containsAll([
        'cc_vaginal_discharge',
        'heaviness_or_bulge_in_vagina',
        'cc_heavy_irregular_periods',
        'cc_lower_abdominal_pain',
      ]));
      // No extra generic baseline items
      expect(resolvedComplaints.any((c) => c['key'] == 'prolapse'), isFalse);
      expect(resolvedComplaints.any((c) => c['key'] == 'stool'), isFalse);
    });
  });
}
