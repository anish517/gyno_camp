import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
  group('PatientModel & Duplicate Detection Tests', () {
    test('generatePatientId creates 5-digit numeric ID', () {
      final id1 = PatientModel.generatePatientId(
        campCode: 'KTM01',
        sequenceNumber: 1,
        year: 2026,
      );
      expect(id1, '00001');

      final id42 = PatientModel.generatePatientId(
        campCode: 'DHN02',
        sequenceNumber: 42,
        year: 2026,
      );
      expect(id42, '00042');

      final id100k = PatientModel.generatePatientId(sequenceNumber: 100000);
      expect(id100k, '100000');
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

    test('normalizePatientId handles 5-digit numbers, Devanagari, blank boxes, and preserves historical GC-* IDs', () {
      // 1. Empty or unfilled boxes preserve empty string (signals auto-generation fallback)
      expect(PatientModel.normalizePatientId(rawInput: '', campCode: 'DHN', year: 2026), '');
      expect(PatientModel.normalizePatientId(rawInput: '   ', campCode: 'DHN', year: 2026), '');
      expect(PatientModel.normalizePatientId(rawInput: '□□□□□', campCode: 'DHN', year: 2026), '');
      expect(PatientModel.normalizePatientId(rawInput: '2083-07-19', campCode: 'DHN', year: 2026), '');
      expect(PatientModel.normalizePatientId(rawInput: '9841234567', campCode: 'DHN', year: 2026), '');

      // 2. Pure digits, Devanagari digits, and spaced boxes resolve to 5-digit numeric IDs
      expect(
        PatientModel.normalizePatientId(rawInput: '42', campCode: 'DHN', year: 2026),
        '00042',
      );
      expect(
        PatientModel.normalizePatientId(rawInput: '00042', campCode: 'DHN', year: 2026),
        '00042',
      );
      expect(
        PatientModel.normalizePatientId(rawInput: '४२', campCode: 'DHN', year: 2026),
        '00042',
      );
      expect(
        PatientModel.normalizePatientId(rawInput: 'Token: 0 0 0 4 2', campCode: 'DHN', year: 2026),
        '00042',
      );
      expect(
        PatientModel.normalizePatientId(rawInput: 'KTM01-00015', campCode: 'KTM01', year: 2026),
        '00015',
      );

      // 3. Existing historical GC-* IDs are preserved without auto-migrating
      expect(
        PatientModel.normalizePatientId(rawInput: 'gc-dhn-2026-00042', campCode: 'DHN', year: 2026),
        'GC-DHN-2026-00042',
      );
      expect(
        PatientModel.normalizePatientId(rawInput: 'GC-DHN-2026-42', campCode: 'DHN', year: 2026),
        'GC-DHN-2026-00042',
      );
    });

    test('isValidPatientIdFormat validates both 5-digit IDs and historical GC-* IDs', () {
      expect(PatientModel.isValidPatientIdFormat('00001'), isTrue);
      expect(PatientModel.isValidPatientIdFormat('00042'), isTrue);
      expect(PatientModel.isValidPatientIdFormat('100000'), isTrue);
      expect(PatientModel.isValidPatientIdFormat('GC-DHN-2026-00042'), isTrue);
      expect(PatientModel.isValidPatientIdFormat('gc-dhn-2026-00042'), isTrue);
      expect(PatientModel.isValidPatientIdFormat('42'), isFalse);
      expect(PatientModel.isValidPatientIdFormat('INVALID'), isFalse);
    });
  });
}
