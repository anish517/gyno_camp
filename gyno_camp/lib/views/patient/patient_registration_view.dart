import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/nepali_localization_service.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/patient_registration_viewmodel.dart';
import 'clinical_assessment_view.dart';

class PatientRegistrationView extends ConsumerStatefulWidget {
  const PatientRegistrationView({super.key});

  @override
  ConsumerState<PatientRegistrationView> createState() => _PatientRegistrationViewState();
}

class _PatientRegistrationViewState extends ConsumerState<PatientRegistrationView> {
  final _firstNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _ageController = TextEditingController();
  final _mobileController = TextEditingController();
  final _wardController = TextEditingController(text: '03');
  final _spouseOrFatherController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _contactMobileController = TextEditingController();

  final List<String> _reasonOptions = [
    'something hanging out',
    'discharge and or itching',
    'problems passing urine',
    'problems passing stool',
    'menstrual problem',
    'infertility',
    'pain',
    'checkup',
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _mobileController.dispose();
    _wardController.dispose();
    _spouseOrFatherController.dispose();
    _contactPersonController.dispose();
    _contactMobileController.dispose();
    super.dispose();
  }

  void _triggerLiveDuplicateCheck() {
    final camp = ref.read(campStateProvider).activeCamp;
    if (camp != null) {
      ref.read(patientRegistrationProvider.notifier).runLiveDuplicateCheck(camp.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientRegistrationProvider);
    final vm = ref.read(patientRegistrationProvider.notifier);
    final camp = ref.watch(campStateProvider).activeCamp;
    final user = ref.watch(authStateProvider).currentUser;
    final device = ref.watch(deviceSecurityProvider).device;

    final isAdult = (int.tryParse(_ageController.text.trim()) ?? 0) >= 20;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient Registration (दर्ता)'),
            Text(
              'Station 1: Demographics & Triage • Yellow Form',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dual Calendar Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 20, color: AppTheme.primaryTeal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Intake Date (दर्ता मिति):',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                        ),
                        Text(
                          NepaliLocalizationService.formatDualCalendarDate(DateTime.now()),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryLight),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      camp?.campCode ?? 'CAMP',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // LIVE DUPLICATE WARNING CARD
            if (state.duplicateResult.hasDuplicate)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade700, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Text(
                          'DUPLICATE DATA DETECTED (दोहोरिएको रेकर्ड)',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state.duplicateResult.matchReasonEn ?? '',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.duplicateResult.matchReasonNe ?? '',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),

            // Section 1: Demographics
            const Text(
              'Patient Demographics (महिलाको विवरण)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(labelText: 'First Name * (नाम)'),
                    onChanged: (val) {
                      vm.updateField(firstName: val);
                      _triggerLiveDuplicateCheck();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _surnameController,
                    decoration: const InputDecoration(labelText: 'Surname * (थर)'),
                    onChanged: (val) {
                      vm.updateField(surname: val);
                      _triggerLiveDuplicateCheck();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Age * (उमेर)'),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      vm.updateField(age: parsed);
                      setState(() {});
                      _triggerLiveDuplicateCheck();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _wardController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Ward No * (वडा नं)'),
                    onChanged: (val) {
                      vm.updateField(ward: val);
                      _triggerLiveDuplicateCheck();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _spouseOrFatherController,
              decoration: InputDecoration(
                labelText: isAdult ? "Husband's Name * (श्रीमानको नाम)" : "Father's Name * (बुबाको नाम)",
                prefixIcon: const Icon(Icons.people_outline),
                helperText: isAdult
                    ? 'Required for duplicate check (age ≥ 20)'
                    : 'Required for duplicate check (age < 20)',
              ),
              onChanged: (val) {
                vm.updateField(spouseOrFatherName: val);
                _triggerLiveDuplicateCheck();
              },
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: "Woman's Mobile (मोबाइल नम्बर)",
                prefixIcon: Icon(Icons.phone_android),
              ),
              onChanged: (val) {
                vm.updateField(mobile: val);
                _triggerLiveDuplicateCheck();
              },
            ),
            const SizedBox(height: 16),

            // Section 2: Marital Status
            const Text(
              'Marital Profile (वैवाहिक स्थिति)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              children: ['married', 'widow', 'unmarried', 'divorced'].map((status) {
                final isSelected = state.maritalStatus == status;
                return ChoiceChip(
                  label: Text('${NepaliLocalizationService.translate(status)} ($status)'),
                  selected: isSelected,
                  onSelected: (_) => vm.updateField(maritalStatus: status),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Section 3: Reason for Gynocamp Visit (8 Yellow Form Checkboxes)
            const Text(
              'Primary Reason for Visit (शिविरमा आउनुको मुख्य कारण)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            Card(
              child: Column(
                children: _reasonOptions.map((reason) {
                  final isChecked = state.selectedReasons.contains(reason);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(
                      '${NepaliLocalizationService.translate(reason)} ($reason)',
                      style: const TextStyle(fontSize: 13),
                    ),
                    value: isChecked,
                    onChanged: (_) => vm.toggleReason(reason),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // Section 4: Informed Consent
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Consent for Treatment (उपचारको सहमति)'),
                    subtitle: const Text('Patient consents to medical examination and clinical treatment.'),
                    value: state.consentTreatment,
                    onChanged: (val) => vm.updateField(consentTreatment: val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Consent to Store Medical Information'),
                    subtitle: const Text('Patient consents to secure recording in the Gynocamp health database.'),
                    value: state.consentStoreMedicalInfo,
                    onChanged: (val) => vm.updateField(consentStoreMedicalInfo: val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (state.errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.dangerRose.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.dangerRose),
                ),
                child: Text(
                  state.errorMessage!,
                  style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                ),
              ),

            // Submit Button
            ElevatedButton.icon(
              icon: state.isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(
                state.isSubmitting
                    ? 'Registering Patient...'
                    : 'Register Patient & Start Clinical Form',
              ),
              onPressed: state.isSubmitting || camp == null
                  ? null
                  : () async {
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);

                      final registered = await vm.submitRegistration(
                        campId: camp.id,
                        campCode: camp.campCode,
                        staffUserId: user?.id ?? 'usr-field',
                        deviceId: device?.deviceId ?? 'dev-field',
                      );

                      if (!mounted) return;

                      if (registered != null) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text('Registered: ${registered.fullName} (ID: ${registered.patientId})'),
                            backgroundColor: AppTheme.successGreen,
                          ),
                        );

                        // Route to Clinical Assessment Form
                        navigator.pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ClinicalAssessmentView(patient: registered),
                          ),
                        );
                      }
                    },
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
