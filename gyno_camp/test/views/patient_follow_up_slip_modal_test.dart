import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/views/patient/patient_follow_up_slip_modal.dart';

void main() {
  group('PatientFollowUpSlipModal Widget Tests', () {
    final samplePatient = PatientModel(
      id: 'pat-slip-01',
      patientId: 'GC-KTM01-2026-00042',
      campId: 'camp-ktm-01',
      campCode: 'KTM01',
      intakeDate: DateTime(2026, 9, 7),
      firstName: 'Suntali',
      surname: 'Tamang',
      age: 48,
      mobile: '9841555666',
      ward: '03',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha Municipality',
      spouseOrFatherName: 'Dorje Tamang',
      relationshipType: 'Husband',
      maritalStatus: 'married',
      reasonsForVisit: const ['something hanging out', 'pain'],
      createdAt: DateTime(2026, 9, 7),
      createdByUserId: 'usr-datataker-01',
      createdByDeviceId: 'dev-tab-01',
      tenantId: 'tenant_bir_hospital',
    );

    final sampleCamp = CampModel(
      id: 'camp-ktm-01',
      campCode: 'KTM01',
      name: 'Kathmandu Community Gyno Health Camp',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha Municipality',
      ward: '03',
      venue: 'Primary Health Care Center',
      startDate: DateTime(2026, 9, 7),
      endDate: DateTime(2026, 9, 10),
      createdAt: DateTime(2026, 9, 6),
      tenantId: 'tenant_bir_hospital',
      organizationName: 'Bir Hospital Gyno Outreach',
    );

    testWidgets('PatientFollowUpSlipModal renders demographics, QR/Barcode and Station Checklist', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientFollowUpSlipModal(
              patient: samplePatient,
              camp: sampleCamp,
              organizationName: 'Bir Hospital Gyno Outreach',
              showProceedButton: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header & Organization
      expect(find.text('PATIENT FOLLOW-UP TOKEN SLIP'), findsOneWidget);
      expect(find.textContaining('BIR HOSPITAL GYNO OUTREACH'), findsOneWidget);
      expect(find.text('Kathmandu Community Gyno Health Camp'), findsOneWidget);

      // Verify Patient ID
      expect(find.text('GC-KTM01-2026-00042'), findsWidgets);

      // Verify Patient Name & Details
      expect(find.text('Suntali Tamang'), findsOneWidget);
      expect(find.textContaining('48 years'), findsOneWidget);
      expect(find.text('Dorje Tamang'), findsOneWidget);
      expect(find.text('9841555666'), findsOneWidget);

      // Verify Station Tracking Checklist
      expect(find.text('Station 1: Registration & Intake'), findsOneWidget);
      expect(find.text('Station 2: Physical & POP Exam'), findsOneWidget);
      expect(find.text('Station 3: Vitals & Lab Testing'), findsOneWidget);
      expect(find.text('Station 4: Doctor Assessment'), findsOneWidget);
      expect(find.text('Station 5: Treatment & Pharmacy'), findsOneWidget);
      expect(find.text('Station 6: Discharge & Referral'), findsOneWidget);

      // Verify Action Buttons
      expect(find.text('Print PDF Slip'), findsOneWidget);
      expect(find.text('Station 2 Chart'), findsOneWidget);
    });

    testWidgets('Tapping Print PDF Slip triggers PDF compilation and displays snackbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientFollowUpSlipModal(
              patient: samplePatient,
              camp: sampleCamp,
              organizationName: 'Bir Hospital Gyno Outreach',
              showProceedButton: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final printButton = find.text('Print PDF Slip');
      expect(printButton, findsOneWidget);

      await tester.ensureVisible(printButton);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(printButton);
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      // Verify success snackbar appears
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('Tapping Station 2 Chart dismisses modal returning true', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await PatientFollowUpSlipModal.show(
                    ctx,
                    patient: samplePatient,
                    camp: sampleCamp,
                    showProceedButton: true,
                  );
                },
                child: const Text('Open Slip'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the dialog
      await tester.tap(find.text('Open Slip'));
      await tester.pumpAndSettle();

      final station2Button = find.text('Station 2 Chart');
      expect(station2Button, findsOneWidget);

      await tester.ensureVisible(station2Button);
      await tester.pumpAndSettle();

      // Tap Station 2 Chart
      await tester.tap(station2Button);
      await tester.pumpAndSettle();

      // Dialog is dismissed and returned true
      expect(find.text('Station 2 Chart'), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('Tapping Close button dismisses modal returning false', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await PatientFollowUpSlipModal.show(
                    ctx,
                    patient: samplePatient,
                    camp: sampleCamp,
                    showProceedButton: true,
                  );
                },
                child: const Text('Open Slip'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the dialog
      await tester.tap(find.text('Open Slip'));
      await tester.pumpAndSettle();

      final closeButton = find.byTooltip('Close Slip');
      expect(closeButton, findsOneWidget);

      // Tap close button
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      // Dialog is dismissed and returned false
      expect(find.text('PATIENT FOLLOW-UP TOKEN SLIP'), findsNothing);
      expect(result, isFalse);
    });
  });
}
