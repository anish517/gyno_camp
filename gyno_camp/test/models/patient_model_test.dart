import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
  group('PatientModel & Duplicate Detection Tests', () {
    test('generatePatientId creates standard formatted ID', () {
      final id1 = PatientModel.generatePatientId(
        campCode: 'KTM01',
        sequenceNumber: 1,
        year: 2026,
      );
      expect(id1, 'GC-KTM01-2026-00001');

      final id42 = PatientModel.generatePatientId(
        campCode: 'DHN02',
        sequenceNumber: 42,
        year: 2026,
      );
      expect(id42, 'GC-DHN02-2026-00042');
    });

    test('Duplicate detector flags duplicate if mobile number matches', () {
      final existingPatient = PatientModel(
        id: 'pat-1',
        patientId: 'GC-KTM01-2026-00001',
        campId: 'camp-1',
        campCode: 'KTM01',
        intakeDate: DateTime(2026, 9, 6),
        firstName: 'Sita',
        surname: 'Tamang',
        age: 35,
        spouseOrFatherName: 'Ram Tamang',
        relationshipType: 'Husband',
        mobile: '9841234567',
        ward: '04',
        createdAt: DateTime(2026, 9, 6),
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
      );

      final isDup = existingPatient.matchesDuplicateCriteria(
        testMobile: '9841234567',
        testFirstName: 'Different',
        testSurname: 'Name',
        testAge: 20,
        testWard: '99',
      );

      expect(isDup, isTrue);
    });

    test('Duplicate detector flags duplicate on Name + Age + Ward + Husband/Father', () {
      // Adult patient (age >= 20) with husband name
      final adultPatient = PatientModel(
        id: 'pat-2',
        patientId: 'GC-KTM01-2026-00002',
        campId: 'camp-1',
        campCode: 'KTM01',
        intakeDate: DateTime(2026, 9, 6),
        firstName: 'Sunita',
        surname: 'Gurung',
        age: 28,
        spouseOrFatherName: 'Bikram Gurung',
        relationshipType: 'Husband',
        mobile: '', // No phone provided
        ward: '05',
        createdAt: DateTime(2026, 9, 6),
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
      );

      // Testing match with slight age tolerance (29 vs 28) and same husband
      final isDup = adultPatient.matchesDuplicateCriteria(
        testMobile: '',
        testFirstName: 'Sunita',
        testSurname: 'Gurung',
        testAge: 29,
        testWard: '05',
        testSpouseOrFather: 'Bikram Gurung',
      );

      expect(isDup, isTrue);

      // Different husband/father name should NOT flag duplicate
      final notDup = adultPatient.matchesDuplicateCriteria(
        testMobile: '',
        testFirstName: 'Sunita',
        testSurname: 'Gurung',
        testAge: 29,
        testWard: '05',
        testSpouseOrFather: 'Hari Bahadur',
      );

      expect(notDup, isFalse);
    });
  });
}
