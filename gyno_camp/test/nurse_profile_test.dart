import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';

void main() {
  group('NurseProfile', () {
    test('parses plain name and strips prefixes', () {
      expect(NurseProfile.parse('Sita Sharma').name, 'Sita Sharma');
      expect(NurseProfile.parse('Nurse Sita Sharma').name, 'Sita Sharma');
      expect(NurseProfile.parse('Sister Sita Sharma').name, 'Sita Sharma');
      expect(NurseProfile.parse('Staff Nurse Sita Sharma').name, 'Sita Sharma');
      expect(NurseProfile.parse('Sita Sharma').registrationNumber, '');
    });

    test('parses NNC / Reg number formats', () {
      final a = NurseProfile.parse('Sita Sharma (NNC: 14256)');
      expect(a.name, 'Sita Sharma');
      expect(a.registrationNumber, '14256');

      final b = NurseProfile.parse('Gita Rai [Reg: 99]');
      expect(b.name, 'Gita Rai');
      expect(b.registrationNumber, '99');

      final c = NurseProfile.parse('Rita KC NNC 123');
      expect(c.name, 'Rita KC');
      expect(c.registrationNumber, '123');
    });

    test('formattedLabel and storage round trip', () {
      const n = NurseProfile(name: 'Sita Sharma', registrationNumber: '14256');
      expect(n.formattedLabel, 'Sita Sharma (NNC: 14256)');
      final parsed = NurseProfile.parse(n.toStorageString());
      expect(parsed.name, n.name);
      expect(parsed.registrationNumber, n.registrationNumber);
    });

    test('parseList respects parentheses and drops empties', () {
      final list = NurseProfile.parseList('Sita (NNC: 1), Gita, ,Rita (NNC: 3)');
      expect(list.map((e) => e.name).toList(), ['Sita', 'Gita', 'Rita']);
      expect(list[0].registrationNumber, '1');
      expect(list[2].registrationNumber, '3');
      expect(NurseProfile.parseList(''), isEmpty);
    });
  });

  group('CampModel nurse fields', () {
    CampModel base() => CampModel(
          id: 'c1',
          campCode: 'KTM01',
          name: 'Camp',
          district: 'Kathmandu',
          municipality: 'KMC',
          ward: '1',
          venue: 'Hall',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 2),
          createdAt: DateTime(2026, 1, 1),
        );

    test('defaults: no nurses, show on forms', () {
      final c = base();
      expect(c.hasNurses, isFalse);
      expect(c.nurseProfiles, isEmpty);
      expect(c.showNurseOnForms, isTrue);
    });

    test('toMap/fromMap round trip keeps NNC and toggle', () {
      final c = base().copyWith(
        nurseNames: ['Sita (NNC: 1)', 'Gita'],
        showNurseOnForms: false,
      );
      final map = c.toMap();
      expect(map['nurse_names'], 'Sita (NNC: 1),Gita');
      expect(map['show_nurse_on_forms'], 0);

      final back = CampModel.fromMap(map);
      expect(back.nurseNames, ['Sita (NNC: 1)', 'Gita']);
      expect(back.showNurseOnForms, isFalse);
      expect(back.nurseProfiles.first.registrationNumber, '1');
    });

    test('legacy map without nurse keys loads cleanly', () {
      final map = base().toMap()
        ..remove('nurse_names')
        ..remove('show_nurse_on_forms');
      final back = CampModel.fromMap(map);
      expect(back.nurseNames, isEmpty);
      expect(back.showNurseOnForms, isTrue);
    });
  });

  group('ClinicalVisitModel nurse fields', () {
    test('toMap/fromMap round trip', () {
      final v = ClinicalVisitModel(
        id: 'v1',
        patientId: 'p1',
        campId: 'c1',
        visitDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        createdByUserId: 'u1',
        attendingNurseNames: const ['Sita', 'Gita'],
        primaryNurseName: 'Sita',
      );
      final map = v.toMap();
      expect(map['attending_nurse_names'], 'Sita,Gita');
      expect(map['primary_nurse_name'], 'Sita');
      final back = ClinicalVisitModel.fromMap(map);
      expect(back.attendingNurseNames, ['Sita', 'Gita']);
      expect(back.primaryNurseName, 'Sita');
    });
  });

  group('OcrScanResultModel nurse fields', () {
    test('merge combines nurses from both pages', () {
      final p1 = OcrScanResultModel.empty().copyWith(attendingNurses: ['A']);
      final p2 = OcrScanResultModel.empty()
          .copyWith(examiningNurse: 'B', attendingNurses: ['A', 'C']);
      final merged = OcrScanResultModel.merge(p1, p2);
      expect(merged.examiningNurse, 'B');
      expect(merged.attendingNurses.toSet(), {'A', 'B', 'C'});
    });

    test('clearExaminingNurse resets the field', () {
      final r = OcrScanResultModel.empty().copyWith(examiningNurse: 'B');
      expect(r.copyWith(clearExaminingNurse: true).examiningNurse, isNull);
    });
  });

  group('OcrFormService nurse parsing', () {
    test('extracts attending nurse from text and avoids GynaeSupport collision', () {
      const ocr = OcrFormService();
      final res = ocr.parseFormText('''
Station 2: POP Examination
POP Stage: Middle 3
Cervix: Normal
Attending Nurse: Sita Thapa (NNC: 1234)
Follow-up: GynaeSupport Nurse
''');
      expect(res.examiningNurse, 'Sita Thapa');
      expect(res.attendingNurses, contains('Sita Thapa'));
      expect(res.followUpDestination, 'GynaeSupport Nurse');
      expect(res.attendingNurses.contains('GynaeSupport Nurse'), false);
    });
  });
}
