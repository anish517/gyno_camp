import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/report_aggregation_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
  group('ReportAggregationService Tests', () {
    late ReportAggregationService aggregationService;
    late CampModel camp;

    setUp(() {
      aggregationService = ReportAggregationService();
      camp = CampModel(
        id: 'camp-test-01',
        campCode: 'KTM01',
        name: 'Kathmandu Free Gyno Health Camp',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        ward: '03',
        venue: 'Primary Health Care Center',
        startDate: DateTime(2026, 3, 10),
        endDate: DateTime(2026, 3, 15),
        createdAt: DateTime(2026, 3, 1),
      );
    });

    PatientModel createPatient({
      required String id,
      required String patientId,
      required int age,
      required String maritalStatus,
      required String ward,
    }) {
      return PatientModel(
        id: id,
        patientId: patientId,
        campId: camp.id,
        campCode: camp.campCode,
        intakeDate: DateTime(2026, 3, 11),
        firstName: 'Patient',
        surname: 'Test',
        age: age,
        ward: ward,
        maritalStatus: maritalStatus,
        mobile: '9800000000',
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
        createdAt: DateTime.now(),
      );
    }

    ClinicalVisitModel createVisit({
      required String id,
      required String patientId,
      int popAnterior = 0,
      int popMiddle = 0,
      int popPosterior = 0,
      int highestPop = 0,
      List<String> diagnoses = const [],
      List<String> medications = const [],
      int? systolicBp,
      int? diastolicBp,
      int? glucose,
      String? urineTest,
      String? pregnancyTest,
      String? pessaryType,
      String? pessarySize,
      String? surgicalReferral,
      String? followUpDestination,
      List<String> counseling = const [],
    }) {
      return ClinicalVisitModel(
        id: id,
        patientId: patientId,
        campId: camp.id,
        visitDate: DateTime(2026, 3, 11),
        popAnteriorStage: popAnterior,
        popMiddleStage: popMiddle,
        popPosteriorStage: popPosterior,
        highestPopStage: highestPop,
        diagnoses: diagnoses,
        medications: medications,
        systolicBp: systolicBp,
        diastolicBp: diastolicBp,
        glucose: glucose,
        urineTest: urineTest,
        pregnancyTest: pregnancyTest,
        pessaryType: pessaryType,
        pessarySize: pessarySize,
        surgicalReferral: surgicalReferral,
        followUpDestination: followUpDestination,
        counseling: counseling,
        createdByUserId: 'usr-1',
        createdAt: DateTime.now(),
      );
    }

    test('correctly tallies demographic age brackets, marital status, and wards', () {
      final patients = [
        createPatient(id: 'p1', patientId: 'PID-1', age: 18, maritalStatus: 'unmarried', ward: '01'),
        createPatient(id: 'p2', patientId: 'PID-2', age: 25, maritalStatus: 'married', ward: '01'),
        createPatient(id: 'p3', patientId: 'PID-3', age: 42, maritalStatus: 'married', ward: '02'),
        createPatient(id: 'p4', patientId: 'PID-4', age: 58, maritalStatus: 'widow', ward: '03'),
        createPatient(id: 'p5', patientId: 'PID-5', age: 72, maritalStatus: 'married', ward: '03'),
      ];

      final summary = aggregationService.aggregate(
        camp: camp,
        patients: patients,
        visits: [],
      );

      expect(summary.totalPatientsRegistered, 5);
      expect(summary.ageGroups['<20'], 1);
      expect(summary.ageGroups['20-35'], 1);
      expect(summary.ageGroups['36-50'], 1);
      expect(summary.ageGroups['51-65'], 1);
      expect(summary.ageGroups['>65'], 1);

      expect(summary.maritalStatusCounts['married'], 3);
      expect(summary.maritalStatusCounts['unmarried'], 1);
      expect(summary.maritalStatusCounts['widow'], 1);

      expect(summary.wardCounts['01'], 2);
      expect(summary.wardCounts['02'], 1);
      expect(summary.wardCounts['03'], 2);
    });

    test('calculates POP compartment staging and clinically significant prolapse percentage', () {
      final visits = [
        // Visit 1: Normal (Stage 0)
        createVisit(
          id: 'v1',
          patientId: 'PID-1',
          popAnterior: 0,
          popMiddle: 0,
          popPosterior: 0,
          highestPop: 0,
        ),
        // Visit 2: Mild Prolapse (Stage 1)
        createVisit(
          id: 'v2',
          patientId: 'PID-2',
          popAnterior: 1,
          popMiddle: 0,
          popPosterior: 0,
          highestPop: 1,
        ),
        // Visit 3: Significant Prolapse (Stage 2)
        createVisit(
          id: 'v3',
          patientId: 'PID-3',
          popAnterior: 2,
          popMiddle: 2,
          popPosterior: 1,
          highestPop: 2,
        ),
        // Visit 4: Severe Prolapse (Stage 3)
        createVisit(
          id: 'v4',
          patientId: 'PID-4',
          popAnterior: 3,
          popMiddle: 3,
          popPosterior: 2,
          highestPop: 3,
        ),
      ];

      final summary = aggregationService.aggregate(
        camp: camp,
        patients: [],
        visits: visits,
      );

      expect(summary.totalVisitsRecorded, 4);
      expect(summary.highestPopStages[0], 1);
      expect(summary.highestPopStages[1], 1);
      expect(summary.highestPopStages[2], 1);
      expect(summary.highestPopStages[3], 1);
      expect(summary.highestPopStages[4], 0);

      // Significant POP (Stage >= 2) = 2 out of 4 (50.0%)
      expect(summary.significantPopCount, 2);
      expect(summary.significantPopPercentage, 50.0);
    });

    test('aggregates clinical diagnoses, vitals alerts, interventions, and pharmacy', () {
      final visits = [
        createVisit(
          id: 'v1',
          patientId: 'PID-1',
          diagnoses: ['PID', 'Cervicitis'],
          medications: ['Ciprofloxacin 500mg', 'Metronidazole 400mg'],
          systolicBp: 150, // Hypertensive
          diastolicBp: 95,
          glucose: 160, // Hyperglycemic
          urineTest: 'pos',
          pregnancyTest: 'neg',
          pessaryType: 'Ring',
          pessarySize: '65mm',
          counseling: ['Pelvic floor exercises'],
          surgicalReferral: 'Scheer Memorial Hospital',
          followUpDestination: 'Health Post',
        ),
        createVisit(
          id: 'v2',
          patientId: 'PID-2',
          diagnoses: ['PID', 'UTI'],
          medications: ['Ciprofloxacin 500mg', 'Ibuprofen 400mg'],
          systolicBp: 120,
          diastolicBp: 80,
          glucose: 90,
          urineTest: 'neg',
          pregnancyTest: 'pos',
          surgicalReferral: 'Model Hospital',
        ),
      ];

      final summary = aggregationService.aggregate(
        camp: camp,
        patients: [],
        visits: visits,
      );

      // Diagnoses: PID (2), Cervicitis (1), UTI (1)
      expect(summary.diagnosisCounts['PID'], 2);
      expect(summary.diagnosisCounts['Cervicitis'], 1);
      expect(summary.diagnosisCounts['UTI'], 1);

      // Vitals
      expect(summary.hypertensionCount, 1);
      expect(summary.hyperglycemiaCount, 1);
      expect(summary.urinePositiveCount, 1);
      expect(summary.pregnancyPositiveCount, 1);

      // Interventions
      expect(summary.totalPessariesInserted, 1);
      expect(summary.pessaryCounts['Ring (65mm)'], 1);
      expect(summary.pelvicFloorCounselingCount, 1);
      expect(summary.totalSurgicalReferrals, 2);
      expect(summary.surgicalReferralCounts['Scheer Memorial Hospital'], 1);
      expect(summary.surgicalReferralCounts['Model Hospital'], 1);
      expect(summary.followUpDestinationCounts['Health Post'], 1);

      // Pharmacy: Ciprofloxacin (2), Metronidazole (1), Ibuprofen (1)
      expect(summary.medicationDispensedCounts['Ciprofloxacin 500mg'], 2);
      expect(summary.medicationDispensedCounts['Metronidazole 400mg'], 1);
      expect(summary.medicationDispensedCounts['Ibuprofen 400mg'], 1);
      expect(summary.totalPrescriptionsCount, 4);
    });
  });
}
