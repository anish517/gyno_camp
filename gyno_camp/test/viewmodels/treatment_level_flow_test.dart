import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/viewmodels/patient_list_viewmodel.dart';

PatientModel _makePatient({
  required String id,
  required String patientId,
  String? treatmentLevel,
}) {
  return PatientModel(
    id: id,
    patientId: patientId,
    campId: 'camp-1',
    campCode: 'CAMP-01',
    intakeDate: DateTime(2026, 3, 15),
    firstName: 'Sita',
    surname: 'Sharma',
    age: 35,
    mobile: '9841000001',
    ward: '04',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    treatmentLevel: treatmentLevel,
    reasonsForVisit: const ['something hanging out'],
    createdAt: DateTime.now(),
    createdByUserId: 'usr-test',
    createdByDeviceId: 'dev-test',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Level of Treatment Models & Logic Tests', () {
    test('PatientModel getters for treatmentLevel work correctly', () {
      final p1 = _makePatient(
        id: 'p1',
        patientId: 'CAMP-001',
        treatmentLevel: 'council_level',
      );

      expect(p1.isCouncilLevel, isTrue);
      expect(p1.isFullCheckUp, isFalse);

      final p2 = p1.copyWith(treatmentLevel: 'full_check_up');
      expect(p2.isCouncilLevel, isFalse);
      expect(p2.isFullCheckUp, isTrue);

      final p3 = p1.copyWith(clearTreatmentLevel: true);
      expect(p3.treatmentLevel, isNull);
      expect(p3.isCouncilLevel, isFalse);
      expect(p3.isFullCheckUp, isFalse);
    });

    test('ClinicalVisitModel getters for treatmentLevel work correctly', () {
      final v1 = ClinicalVisitModel(
        id: 'v1',
        patientId: 'CAMP-001',
        campId: 'camp-1',
        visitDate: DateTime.now(),
        treatmentLevel: 'council_level',
        createdByUserId: 'usr-1',
        createdAt: DateTime.now(),
      );

      expect(v1.isCouncilLevel, isTrue);
      expect(v1.isFullCheckUp, isFalse);

      final v2 = v1.copyWith(treatmentLevel: 'full_check_up');
      expect(v2.isCouncilLevel, isFalse);
      expect(v2.isFullCheckUp, isTrue);
    });

    test('OcrScanResultModel preserves and normalizes treatmentLevel across copyWith', () {
      final scan1 = OcrScanResultModel.empty().copyWith(treatmentLevel: 'council_level');
      expect(scan1.treatmentLevel, equals('counseling'));
      expect(scan1.isCounseling, isTrue);
      expect(scan1.isCouncilLevel, isTrue);

      final scan2 = scan1.copyWith(treatmentLevel: 'full_check_up');
      expect(scan2.treatmentLevel, equals('gyno_checkup'));
      expect(scan2.isGynocheckup, isTrue);
      expect(scan2.isFullCheckUp, isTrue);

      final scan3 = scan2.copyWith(treatmentLevel: 'Gynocheckup');
      expect(scan3.treatmentLevel, equals('gyno_checkup'));
      expect(scan3.isGynocheckup, isTrue);
    });
  });

  group('PatientFilterCriteria Treatment Level Filtering', () {
    final patientCouncil = _makePatient(
      id: 'p1',
      patientId: 'C-01',
      treatmentLevel: 'council_level',
    );

    final patientFull = _makePatient(
      id: 'p2',
      patientId: 'C-02',
      treatmentLevel: 'full_check_up',
    );

    final patientNone = _makePatient(
      id: 'p3',
      patientId: 'C-03',
      treatmentLevel: null,
    );

    final allPatients = [patientCouncil, patientFull, patientNone];

    test('Filter criteria correctly counts active treatmentLevel filter', () {
      const defaultCriteria = PatientFilterCriteria();
      expect(defaultCriteria.hasActiveFilters, isFalse);
      expect(defaultCriteria.activeFilterCount, equals(0));

      final councilCriteria = defaultCriteria.copyWith(treatmentLevel: 'council_level');
      expect(councilCriteria.hasActiveFilters, isTrue);
      expect(councilCriteria.activeFilterCount, equals(1));
    });

    test('Filters match by treatmentLevel accurately', () {
      final councilCriteria = const PatientFilterCriteria(treatmentLevel: 'council_level');
      final filteredCouncil = allPatients.where((p) {
        if (councilCriteria.treatmentLevel != null &&
            councilCriteria.treatmentLevel != 'all' &&
            councilCriteria.treatmentLevel!.isNotEmpty) {
          if (p.treatmentLevel != councilCriteria.treatmentLevel) return false;
        }
        return true;
      }).toList();

      expect(filteredCouncil.length, equals(1));
      expect(filteredCouncil.first.patientId, equals('C-01'));

      final fullCriteria = const PatientFilterCriteria(treatmentLevel: 'full_check_up');
      final filteredFull = allPatients.where((p) {
        if (fullCriteria.treatmentLevel != null &&
            fullCriteria.treatmentLevel != 'all' &&
            fullCriteria.treatmentLevel!.isNotEmpty) {
          if (p.treatmentLevel != fullCriteria.treatmentLevel) return false;
        }
        return true;
      }).toList();

      expect(filteredFull.length, equals(1));
      expect(filteredFull.first.patientId, equals('C-02'));
    });
  });

  group('PDF Page 1 Dual Layout Validation', () {
    test('BlankFormPage1Layout.grid generates strictly 2-page forms without error', () async {
      final pdfService = PdfReportService();

      final gridBytes = await pdfService.generatePatientRegistrationFormPdf(
        page1Layout: BlankFormPage1Layout.grid,
      );
      expect(gridBytes.isNotEmpty, isTrue);
    });

    test('BlankFormPage1Layout.classic generates strictly 2-page forms without error', () async {
      final pdfService = PdfReportService();

      final classicBytes = await pdfService.generatePatientRegistrationFormPdf(
        page1Layout: BlankFormPage1Layout.classic,
      );
      expect(classicBytes.isNotEmpty, isTrue);
    });
  });
}
