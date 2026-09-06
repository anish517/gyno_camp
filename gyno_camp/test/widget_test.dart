import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/views/auth/login_view.dart';
import 'package:gyno_camp/views/patient/clinical_assessment_view.dart';
import 'package:gyno_camp/views/patient/patient_list_view.dart';
import 'package:gyno_camp/views/patient/patient_registration_view.dart';
import 'package:gyno_camp/views/security/app_lock_pin_view.dart';
import 'package:gyno_camp/views/security/device_activation_view.dart';

void main() {
  group('Widget & View Tests (MVVM)', () {
    testWidgets('LoginView renders all 3 user role selection options', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const LoginView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Select User Role to Continue:'), findsOneWidget);
      expect(find.text('Data Taker (Field Staff)'), findsOneWidget);
      expect(find.text('Super Admin'), findsOneWidget);
      expect(find.text('Data Analyst'), findsOneWidget);
    });

    testWidgets('DeviceActivationView displays hardware signature card and activation fields', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const DeviceActivationView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('HARDWARE SIGNATURE'), findsOneWidget);
      expect(find.byIcon(Icons.security), findsOneWidget);
    });

    testWidgets('AppLockPinView renders PIN input keypad and biometric icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AppLockPinView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('PatientRegistrationView renders demographic fields and consent switches', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PatientRegistrationView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Patient Registration (दर्ता)'), findsOneWidget);
      expect(find.text('Patient Demographics (महिलाको विवरण)'), findsOneWidget);
      expect(find.text('Marital Profile (वैवाहिक स्थिति)'), findsOneWidget);
      expect(find.text('Primary Reason for Visit (शिविरमा आउनुको मुख्य कारण)'), findsOneWidget);
      expect(find.text('Consent for Treatment (उपचारको सहमति)'), findsOneWidget);
    });

    testWidgets('ClinicalAssessmentView renders all 6 Station Steppers and vitals fields', (WidgetTester tester) async {
      final samplePatient = PatientModel(
        id: 'pat-test',
        patientId: 'GC-KTM-2026-00001',
        campId: 'camp-ktm-01',
        campCode: 'KTM',
        intakeDate: DateTime.now(),
        firstName: 'Sita',
        surname: 'Sharma',
        age: 32,
        mobile: '9841234567',
        ward: '03',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: ClinicalAssessmentView(patient: samplePatient),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1. Anamnesis'), findsOneWidget);
      expect(find.text('2. Exam & POP'), findsOneWidget);
      expect(find.text('3. Vitals & Lab'), findsOneWidget);
      expect(find.text('4. Diagnoses'), findsOneWidget);
      expect(find.text('5. Treatment'), findsOneWidget);
      expect(find.text('6. Outtake'), findsOneWidget);
    });

    testWidgets('PatientListView renders camp patient roll interface', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const PatientListView(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Camp Patient Roll'), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });
  });
}
