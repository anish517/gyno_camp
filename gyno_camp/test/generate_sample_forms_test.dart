import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate Blank and Filled Yellow Forms into test_samples directory', () async {
    final sampleCamp = CampModel(
      id: 'camp-ktm-01',
      campCode: 'KTM01',
      name: 'Budhanilkantha Outreach Gyno Camp',
      province: 'Bagmati',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '04',
      venue: 'Budhanilkantha Health Center',
      startDate: DateTime(2026, 9, 6),
      endDate: DateTime(2026, 9, 8),
      status: CampStatus.open,
      tenantId: 'tenant_mohp_nepal',
      organizationName: 'Ministry of Health & Population - Nepal Rural Health',
      createdAt: DateTime(2026, 9, 1),
    );

    final samplePatient = PatientModel(
      id: 'pat-maya-01',
      patientId: 'GC-KTM01-2026-001',
      campId: 'camp-ktm-01',
      campCode: 'KTM01',
      intakeDate: DateTime(2026, 9, 6),
      firstName: 'Maya',
      surname: 'Tamang',
      age: 44,
      spouseOrFatherName: 'Som Bahadur Tamang',
      relationshipType: 'Husband',
      mobile: '9841987654',
      province: 'Bagmati',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '04',
      contactPerson: 'Bishal Tamang',
      contactMobile: '9851234567',
      maritalStatus: 'married',
      maritalAge: 18,
      reasonsForVisit: [
        'Something hanging out',
        'Discharge and or itching',
        'Problems passing urine',
        'Menstrual problem',
      ],
      consentTreatment: true,
      consentStoreMedicalInfo: true,
      createdAt: DateTime(2026, 9, 6, 9, 30),
      createdByUserId: 'usr-nurse-1',
      createdByDeviceId: 'dev-field-tab-01',
      tenantId: 'tenant_mohp_nepal',
      isSynced: false,
    );

    final sampleVisit = ClinicalVisitModel(
      id: 'vis-maya-01',
      patientId: 'GC-KTM01-2026-001',
      campId: 'camp-ktm-01',
      visitDate: DateTime(2026, 9, 6),
      deliveries: 3,
      livingChildren: 3,
      abortions: 0,
      anamnesisComplaints: {
        'complaintsDuration': '> 1 year',
        'clinicalComplaints': [
          'Lower Abdominal Pain',
          'White / Foul Discharge',
          'Pelvic Heaviness',
          'Mass Per Vagina',
        ],
      },
      uterusInside: false,
      pelvicFloorTone: 'hypertonic',
      popAnteriorStage: 2,
      popMiddleStage: 3,
      popPosteriorStage: 1,
      highestPopStage: 3,
      cervixRemarks: 'Erosion, contact bleeding',
      vaginaRemarks: 'Mild atrophic vaginitis, discharge',
      systolicBp: 130,
      diastolicBp: 85,
      pulse: 78,
      spo2: 98,
      glucose: 115,
      urineTest: 'protein, glucose',
      pregnancyTest: 'neg',
      diagnoses: ['POP', 'Candidal Infection', 'Hypertension'],
      medications: ['Ring Pessary', 'Metronidazole', 'Fluconazole'],
      pessaryType: 'ring',
      pessarySize: '65',
      counseling: ['Pelvic floor exercises', 'Hygiene care'],
      surgicalReferral: 'Scheer Memorial Hospital',
      followUpNeeded: true,
      followUpDestination: 'GynaeSupport Nurse in 2 weeks',
      outtakeNotes: 'Fitted size 65mm ring pessary. Review at health center in 2 weeks.',
      createdByUserId: 'usr-doc-01',
      tenantId: 'tenant_mohp_nepal',
      isSynced: false,
      createdAt: DateTime(2026, 9, 6, 11, 0),
    );

    final pdfService = PdfReportService();

    // 1. Generate Blank Yellow Form (2 Pages) - EXACT MATCH WITH PHYSICAL BLANK FORM
    final blankBytes = await pdfService.generatePatientRegistrationFormPdf(
      camp: sampleCamp,
      organizationName: 'Ministry of Health & Population - Nepal Rural Health',
    );
    expect(blankBytes.isNotEmpty, true);
    final blankFile = File('test_samples/sample_yellow_form_blank.pdf');
    blankFile.writeAsBytesSync(blankBytes);
    expect(blankFile.existsSync(), true);

    // 2. Generate Pre-Filled Yellow Form (2 Pages) - EXACT SAME FORMAT WITH CLINICAL DATA POPULATED
    final filledBytes = await pdfService.generatePatientRegistrationFormPdf(
      patient: samplePatient,
      camp: sampleCamp,
      visit: sampleVisit,
      organizationName: 'Ministry of Health & Population - Nepal Rural Health',
    );
    expect(filledBytes.isNotEmpty, true);
    final filledFile = File('test_samples/sample_yellow_form_filled.pdf');
    filledFile.writeAsBytesSync(filledBytes);
    expect(filledFile.existsSync(), true);

    // Sample forms successfully generated in test_samples directory
  });
}
