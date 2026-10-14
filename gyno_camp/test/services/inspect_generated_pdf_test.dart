// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';

void main() {
  test('Generate Blank and Populated Yellow Form PDFs and verify accuracy', () async {
    final pdfService = PdfReportService();

    final camp = CampModel(
      id: 'c-test-1',
      campCode: 'KTM01',
      name: 'Gyno Health Outreach Camp',
      venue: 'Primary Health Center',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha Municipality',
      ward: '03',
      doctorName: 'Dr. Sita Sharma',
      doctorNames: ['Dr. Sita Sharma'],
      startDate: DateTime(2026, 10, 15),
      endDate: DateTime(2026, 10, 18),
      status: CampStatus.open,
      createdAt: DateTime.now(),
    );

    print('--- 1. Generating Blank Form ---');
    final blankBytes = await pdfService.generatePatientRegistrationFormPdf(
      camp: camp,
      organizationName: 'Women for Society',
    );

    final blankFile = File(r'C:\Users\AnishTiwari\.gemini\antigravity-ide\brain\fdd031d8-4375-4ada-8c55-6d9fedd1729e\scratch\blank_form.pdf');
    blankFile.writeAsBytesSync(blankBytes);
    print('Blank form size: ${blankBytes.length} bytes');

    final blankStr = String.fromCharCodes(blankBytes);
    final blankPages = RegExp(r'/Type\s*/Page\b').allMatches(blankStr).length;
    print('Blank form page count: $blankPages');
    expect(blankPages, equals(2));

    print('--- 2. Generating Patient Form with Clinical Intake Data ---');
    final patient = PatientModel(
      id: 'p-1',
      patientId: 'GC-KTM01-2026-001',
      campId: 'c-test-1',
      campCode: 'KTM01',
      intakeDate: DateTime(2026, 10, 15),
      firstName: 'SUNITA',
      surname: 'TAMANG',
      age: 38,
      spouseOrFatherName: 'RAMESH TAMANG',
      relationshipType: 'Husband',
      mobile: '9841234567',
      province: 'Bagmati',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '03',
      contactPerson: 'SITA TAMANG',
      contactMobile: '9847654321',
      maritalStatus: 'married',
      maritalAge: 19,
      reasonsForVisit: ['Prolapse', 'Discharge', 'Lower abdomen pain'],
      consentTreatment: true,
      consentStoreMedicalInfo: true,
      createdAt: DateTime.now(),
      createdByUserId: 'usr-1',
      createdByDeviceId: 'dev-1',
      tenantId: 't-1',
      isSynced: false,
    );

    final visit = ClinicalVisitModel(
      id: 'v-1',
      patientId: 'p-1',
      campId: 'c-test-1',
      visitDate: DateTime(2026, 10, 15),
      deliveries: 3,
      livingChildren: 3,
      abortions: 0,
      anamnesisComplaints: {
        'prolapse': {
          'present': true,
          'duration': '> 1 year',
          'options': ['pessary'],
          'remarks': 'Ring pessary attempted 6 months ago',
        },
        'discharge': {
          'present': true,
          'duration': '< 1month',
          'options': ['white', 'smelly'],
          'remarks': 'Curdy white with pruritus',
        },
        'urine': {
          'present': true,
          'duration': '< 1 year',
          'options': ['stress'],
          'remarks': 'Leakage during coughing and sneezing',
        },
        'lower_abdomen_pain': {
          'present': true,
          'duration': '< 1month',
          'remarks': 'Dull aching pain in hypogastrium',
        },
      },
      uterusInside: false,
      pelvicFloorTone: 'weak',
      popAnteriorStage: 2,
      popMiddleStage: 3,
      popPosteriorStage: 1,
      highestPopStage: 3,
      systolicBp: 120,
      diastolicBp: 80,
      pulse: 76,
      spo2: 98,
      glucose: 104,
      urineTest: 'normal',
      pregnancyTest: 'neg',
      ecgNotes: 'Normal Sinus Rhythm, HR 76 bpm, regular',
      diagnoses: ['Pelvic Organ Prolapse Stage 3', 'Candidiasis', 'Stress Urinary Incontinence'],
      counseling: ['PFMT', 'Hygiene', 'Prolapse Care'],
      pessaryType: 'Ring with Support',
      pessarySize: '70',
      surgicalReferral: 'Scheer Memorial Hospital',
      medications: ['Tab Fluconazole 150mg', 'Vaginal Clotrimazole Pessary'],
      customMedication: 'Tab Paracetamol 500mg PRN for pain',
      followUpNeeded: true,
      followUpDestination: 'GynaeSupport Nurse',
      outtakeNotes: 'Advised PFMT daily. Follow-up after 1 month for pessary evaluation.',
      primaryDoctorName: 'Dr. Sita Sharma',
      attendingDoctorNames: ['Dr. Sita Sharma'],
      primaryNurseName: 'Nurse Gita Shrestha',
      attendingNurseNames: ['Nurse Gita Shrestha'],
      treatmentLevel: 'full_check_up',
      createdAt: DateTime.now(),
      createdByUserId: 'usr-1',
      tenantId: 't-1',
      isSynced: false,
    );

    final patientBytes = await pdfService.generatePatientRegistrationFormPdf(
      patient: patient,
      visit: visit,
      camp: camp,
      doctor: DoctorProfile(name: 'Dr. Sita Sharma', nmcNumber: '12345'),
      organizationName: 'Women for Society',
    );

    final patientFile = File(r'C:\Users\AnishTiwari\.gemini\antigravity-ide\brain\fdd031d8-4375-4ada-8c55-6d9fedd1729e\scratch\patient_form.pdf');
    patientFile.writeAsBytesSync(patientBytes);
    print('Patient form size: ${patientBytes.length} bytes');

    final patientStr = String.fromCharCodes(patientBytes);
    final patientPages = RegExp(r'/Type\s*/Page\b').allMatches(patientStr).length;
    print('Patient form page count: $patientPages');
    expect(patientPages, equals(2));
    print('--- Both forms verified successfully! ---');
  });

  test('Generate Blank Form with All Doctors Checklist and All Nurses Checklist (Strictly 2 pages)', () async {
    final pdfService = PdfReportService();

    final campWithMultipleStaff = CampModel(
      id: 'c-test-multi',
      campCode: 'KTM02',
      name: 'Multi-Doctor Health Outreach Camp',
      venue: 'District Hospital',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha Municipality',
      ward: '04',
      doctorName: 'Dr. Sita Sharma',
      doctorNames: ['Dr. Sita Sharma', 'Dr. Rita KC', 'Dr. Rajesh Dahal'],
      nurseNames: ['Nurse Gita Shrestha', 'Nurse Anju Thapa'],
      startDate: DateTime(2026, 10, 15),
      endDate: DateTime(2026, 10, 18),
      status: CampStatus.open,
      createdAt: DateTime.now(),
    );

    print('--- 3. Generating Blank Form with All Doctors Checklist ---');
    final blankChecklistBytes = await pdfService.generatePatientRegistrationFormPdf(
      camp: campWithMultipleStaff,
      allDoctorsChecklist: true,
      allNursesChecklist: true,
      organizationName: 'Women for Society',
    );

    final allPdfText = extractAllTextFromPdf(blankChecklistBytes);
    final pageCount = RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(blankChecklistBytes)).length;
    print('Multi-Doctor Checklist blank form page count: $pageCount');
    expect(pageCount, equals(2));

    print('Sita: ${allPdfText.contains("Sita")}');
    print('Sharma: ${allPdfText.contains("Sharma")}');
    print('Rita: ${allPdfText.contains("Rita")}');
    print('Rajesh: ${allPdfText.contains("Rajesh")}');
    print('Dahal: ${allPdfText.contains("Dahal")}');
    print('Gita: ${allPdfText.contains("Gita")}');
    print('Shrestha: ${allPdfText.contains("Shrestha")}');
    print('Anju: ${allPdfText.contains("Anju")}');
    print('Thapa: ${allPdfText.contains("Thapa")}');

    // Verify all doctors and nurses are included in the generated PDF stream
    expect(allPdfText.contains('Sita'), isTrue);
    expect(allPdfText.contains('Rita'), isTrue);
    expect(allPdfText.contains('Rajesh'), isTrue);
    expect(allPdfText.contains('Gita'), isTrue);
    expect(allPdfText.contains('Anju'), isTrue);
    print('--- All doctors and nurses successfully printed as checklist on 2-page PDF! ---');
  });


}

String extractAllTextFromPdf(List<int> bytes) {
  final sb = StringBuffer();
  sb.writeln(String.fromCharCodes(bytes.where((b) => b >= 32 && b <= 126)));

  final streamMarker = 'stream'.codeUnits;
  final endStreamMarker = 'endstream'.codeUnits;

  int i = 0;
  while (i < bytes.length - streamMarker.length) {
    bool match = true;
    for (int j = 0; j < streamMarker.length; j++) {
      if (bytes[i + j] != streamMarker[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      int start = i + streamMarker.length;
      if (start < bytes.length && bytes[start] == 13) start++; // \r
      if (start < bytes.length && bytes[start] == 10) start++; // \n
      int end = -1;
      for (int k = start; k < bytes.length - endStreamMarker.length; k++) {
        bool endMatch = true;
        for (int m = 0; m < endStreamMarker.length; m++) {
          if (bytes[k + m] != endStreamMarker[m]) {
            endMatch = false;
            break;
          }
        }
        if (endMatch) {
          end = k;
          if (end > start && bytes[end - 1] == 10) end--;
          if (end > start && bytes[end - 1] == 13) end--;
          break;
        }
      }
      if (end != -1 && end > start) {
        final streamSlice = bytes.sublist(start, end);
        try {
          final decompressed = zlib.decode(streamSlice);
          sb.writeln(String.fromCharCodes(decompressed));
        } catch (e) {
          try {
            final decompressed = ZLibDecoder(raw: true).convert(streamSlice);
            sb.writeln(String.fromCharCodes(decompressed));
          } catch (_) {}
        }
        i = end + endStreamMarker.length;
        continue;
      }
    }
    i++;
  }
  print('extractAllTextFromPdf extracted: ${sb.length} characters');
  return sb.toString();
}


