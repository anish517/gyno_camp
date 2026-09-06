import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/duplicate_detection_service.dart';
import 'package:gyno_camp/core/services/nepali_localization_service.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
  group('DuplicateDetectionService Tests', () {
    final existingPatients = [
      PatientModel(
        id: 'pat-1',
        patientId: 'GC-KTM-2026-00001',
        campId: 'camp-1',
        campCode: 'KTM',
        intakeDate: DateTime(2026, 3, 10),
        firstName: 'Sita',
        surname: 'Sharma',
        age: 32,
        spouseOrFatherName: 'Ram Sharma',
        relationshipType: 'Husband',
        mobile: '9841234567',
        ward: '03',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
      ),
      PatientModel(
        id: 'pat-2',
        patientId: 'GC-KTM-2026-00002',
        campId: 'camp-1',
        campCode: 'KTM',
        intakeDate: DateTime(2026, 3, 10),
        firstName: 'Pooja',
        surname: 'Tamang',
        age: 18,
        spouseOrFatherName: 'Bir Bahadur Tamang',
        relationshipType: 'Father',
        mobile: '',
        ward: '05',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
      ),
    ];

    test('Identifies duplicate on exact mobile number match', () {
      final result = DuplicateDetectionService.check(
        existingPatients: existingPatients,
        firstName: 'Geeta',
        surname: 'Adhikari',
        age: 45,
        mobile: '9841234567', // Same as Sita
        ward: '10',
      );

      expect(result.isDuplicate, isTrue);
      expect(result.matchedPatient?.patientId, 'GC-KTM-2026-00001');
      expect(result.reason?.toLowerCase(), contains('mobile number'));
    });

    test('Identifies duplicate on Name + Ward + Age +/- 1 tolerance', () {
      // Age 33 (existing is 32) -> within +/- 1 year
      final result = DuplicateDetectionService.check(
        existingPatients: existingPatients,
        firstName: 'sita',
        surname: 'sharma',
        age: 33,
        mobile: '9800000000',
        ward: '03',
        spouseOrFatherName: 'Ram Sharma',
      );

      expect(result.isDuplicate, isTrue);
      expect(result.matchedPatient?.patientId, 'GC-KTM-2026-00001');
      expect(result.reason, contains('match on Name'));
    });

    test('Does not flag duplicate if age difference is greater than 1 year', () {
      final result = DuplicateDetectionService.check(
        existingPatients: existingPatients,
        firstName: 'Sita',
        surname: 'Sharma',
        age: 35, // 3 years older
        mobile: '9800000000',
        ward: '03',
      );

      expect(result.isDuplicate, isFalse);
      expect(result.matchedPatient, isNull);
    });

    test('Under 20 years patient matches Father name', () {
      final result = DuplicateDetectionService.check(
        existingPatients: existingPatients,
        firstName: 'pooja',
        surname: 'tamang',
        age: 18,
        mobile: '',
        ward: '05',
        spouseOrFatherName: 'Bir Bahadur Tamang',
      );

      expect(result.isDuplicate, isTrue);
      expect(result.matchedPatient?.patientId, 'GC-KTM-2026-00002');
    });

    test('Unmarried adult patient (age >= 20) matches Father/Guardian name', () {
      final adultUnmarriedPatients = [
        PatientModel(
          id: 'pat-unm',
          patientId: 'GC-KTM-2026-00009',
          campId: 'camp-1',
          campCode: 'KTM',
          intakeDate: DateTime(2026, 3, 10),
          firstName: 'Anjali',
          surname: 'Shrestha',
          age: 26,
          spouseOrFatherName: 'Gopal Shrestha',
          relationshipType: 'Father',
          mobile: '',
          ward: '02',
          createdAt: DateTime.now(),
          createdByUserId: 'usr-1',
          createdByDeviceId: 'dev-1',
        ),
      ];

      final result = DuplicateDetectionService.check(
        existingPatients: adultUnmarriedPatients,
        firstName: 'Anjali',
        surname: 'Shrestha',
        age: 26,
        mobile: '',
        ward: '02',
        spouseOrFatherName: 'Gopal Shrestha',
        maritalStatus: 'unmarried',
      );

      expect(result.isDuplicate, isTrue);
      expect(result.matchedPatient?.patientId, 'GC-KTM-2026-00009');
      expect(result.reason, contains("Father's/Guardian's name"));
    });

    test('Does not flag duplicate if ward is different', () {
      final result = DuplicateDetectionService.check(
        existingPatients: existingPatients,
        firstName: 'Sita',
        surname: 'Sharma',
        age: 32,
        mobile: '9811111111',
        ward: '08', // Different ward
      );

      expect(result.isDuplicate, isFalse);
    });
  });

  group('NepaliLocalizationService Tests', () {
    test('Translates standard clinical diagnoses and symptoms accurately', () {
      expect(NepaliLocalizationService.translate('POP'), 'आङ खस्ने समस्या (POP)');
      expect(NepaliLocalizationService.translate('UTI'), 'पिसाब संक्रमण (UTI)');
      expect(NepaliLocalizationService.translate('Hypertension'), 'उच्च रक्तचाप (High BP)');
      expect(NepaliLocalizationService.translate('ring pessary'), 'रिङ पेसरी');
      expect(NepaliLocalizationService.translate('NonExistentTerm'), 'NonExistentTerm');
    });

    test('Formats Gregorian dates to Nepali Bikram Sambat representation', () {
      final dt = DateTime(2026, 3, 15);
      final formatted = NepaliLocalizationService.formatNepaliDate(dt);
      expect(formatted, contains('2083'));
      expect(formatted, contains('BS'));
    });
  });
}
