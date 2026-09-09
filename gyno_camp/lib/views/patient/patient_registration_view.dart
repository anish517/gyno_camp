import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/nepali_localization_service.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/camp_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../models/camp_model.dart';
import '../../models/patient_model.dart';
import '../../viewmodels/patient_list_viewmodel.dart';
import '../../viewmodels/patient_registration_viewmodel.dart';
import 'clinical_assessment_view.dart';
import 'patient_follow_up_slip_modal.dart';

class PatientRegistrationView extends ConsumerStatefulWidget {
  const PatientRegistrationView({super.key});

  @override
  ConsumerState<PatientRegistrationView> createState() =>
      _PatientRegistrationViewState();
}

class _PatientRegistrationViewState
    extends ConsumerState<PatientRegistrationView> {
  final _firstNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _ageController = TextEditingController();
  final _mobileController = TextEditingController();
  final _wardController = TextEditingController();
  final _districtController = TextEditingController();
  final _municipalityController = TextEditingController();
  final _spouseOrFatherController = TextEditingController();
  final _maritalAgeController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _contactMobileController = TextEditingController();

  // Reason options with proper clinical display labels (matching Yellow Form page 1)
  // Keys are the stored values, Values are clinical display names for staff
  final Map<String, String> _reasonOptions = {
    'something hanging out': 'Something Hanging Out (Uterine / Vaginal Prolapse)',
    'discharge and or itching': 'Vaginal Discharge &/or Itching (स्राव / खटिरो)',
    'problems passing urine': 'Problems Passing Urine (पेसाब सम्बन्धी समस्या)',
    'problems passing stool': 'Problems Passing Stool (दिसा सम्बन्धी समस्या)',
    'menstrual problem': 'Menstrual Problem (महिनावारी सम्बन्धी समस्या)',
    'infertility': 'Infertility (बाँझोपन)',
    'pain': 'Pelvic / Abdominal Pain (दुखाई)',
    'checkup': 'General Gynaecological Checkup (सामान्य जाँच)',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyActiveCampLocation();
    });
  }

  void _applyActiveCampLocation() {
    final camp = ref.read(campStateProvider).activeCamp;
    if (camp != null) {
      ref
          .read(patientRegistrationProvider.notifier)
          .updateField(
            district: camp.district,
            municipality: camp.municipality,
            ward: camp.ward,
          );
      if (_districtController.text.isEmpty && camp.district.isNotEmpty) {
        _districtController.text = camp.district;
      }
      if (_municipalityController.text.isEmpty &&
          camp.municipality.isNotEmpty) {
        _municipalityController.text = camp.municipality;
      }
      if (_wardController.text.isEmpty && camp.ward.isNotEmpty) {
        _wardController.text = camp.ward;
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _mobileController.dispose();
    _wardController.dispose();
    _districtController.dispose();
    _municipalityController.dispose();
    _spouseOrFatherController.dispose();
    _maritalAgeController.dispose();
    _contactPersonController.dispose();
    _contactMobileController.dispose();
    super.dispose();
  }

  void _triggerLiveDuplicateCheck() {
    final camp = ref.read(campStateProvider).activeCamp;
    if (camp != null) {
      ref
          .read(patientRegistrationProvider.notifier)
          .runLiveDuplicateCheck(camp.id);
    }
  }

  Future<void> _handlePostRegistrationSlip(
    PatientModel registered,
    CampModel camp,
  ) async {
    if (!mounted) return;
    final orgName = camp.organizationName.isNotEmpty
        ? camp.organizationName
        : 'Nepal Gyno Health Outreach Network';

    final proceedToStation2 = await PatientFollowUpSlipModal.show(
      context,
      patient: registered,
      camp: camp,
      organizationName: orgName,
      showProceedButton: true,
    );
    if (!mounted) return;

    if (proceedToStation2 == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ClinicalAssessmentView(patient: registered),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _fillSamplePatient() {
    final camp = ref.read(campStateProvider).activeCamp;
    final ward = (camp?.ward.isNotEmpty == true) ? camp!.ward : '03';
    final district = (camp?.district.isNotEmpty == true)
        ? camp!.district
        : 'Kathmandu';
    final municipality = (camp?.municipality.isNotEmpty == true)
        ? camp!.municipality
        : 'Budhanilkantha Municipality';

    _firstNameController.text = 'Suntali';
    _surnameController.text = 'Tamang';
    _ageController.text = '48';
    _wardController.text = ward;
    _districtController.text = district;
    _municipalityController.text = municipality;
    _spouseOrFatherController.text = 'Dorje Tamang';
    _maritalAgeController.text = '18';
    _mobileController.text = '9841555666';
    _contactPersonController.text = 'Pasang Tamang (Son)';
    _contactMobileController.text = '9811223344';

    final vm = ref.read(patientRegistrationProvider.notifier);
    vm.updateField(
      firstName: 'Suntali',
      surname: 'Tamang',
      age: 48,
      ward: ward,
      district: district,
      municipality: municipality,
      spouseOrFatherName: 'Dorje Tamang',
      relationshipType: 'Husband',
      maritalStatus: 'married',
      maritalAge: 18,
      mobile: '9841555666',
      contactPerson: 'Pasang Tamang (Son)',
      contactMobile: '9811223344',
      consentTreatment: true,
      consentStoreMedicalInfo: true,
    );
    if (!ref
        .read(patientRegistrationProvider)
        .selectedReasons
        .contains('something hanging out')) {
      vm.toggleReason('something hanging out');
    }
    setState(() {});
    _triggerLiveDuplicateCheck();
  }

  void _clearForm() {
    _firstNameController.clear();
    _surnameController.clear();
    _ageController.clear();
    _mobileController.clear();
    _spouseOrFatherController.clear();
    _maritalAgeController.clear();
    _contactPersonController.clear();
    _contactMobileController.clear();

    final camp = ref.read(campStateProvider).activeCamp;
    _wardController.text = camp?.ward ?? '';
    _districtController.text = camp?.district ?? '';
    _municipalityController.text = camp?.municipality ?? '';

    ref
        .read(patientRegistrationProvider.notifier)
        .reset(
          ward: camp?.ward ?? '',
          district: camp?.district ?? '',
          municipality: camp?.municipality ?? '',
        );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientRegistrationProvider);
    final vm = ref.read(patientRegistrationProvider.notifier);
    final camp = ref.watch(campStateProvider).activeCamp;
    final user = ref.watch(authStateProvider).currentUser;
    final device = ref.watch(deviceSecurityProvider).device;

    final ageVal = int.tryParse(_ageController.text.trim()) ?? 0;
    final isAdult = ageVal >= 20;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient Registration (दर्ता)'),
            Text(
              'Station 1: Demographics & Triage • Yellow Form',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          if (kDebugMode)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
              label: const Text(
                'Demo Sample',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: _fillSamplePatient,
            ),
          IconButton(
            tooltip: 'Clear Form',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _clearForm,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 0. Form Step Progress Indicator
                _buildFormStepBar(state),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.calendar_today_rounded,
                          size: 20,
                          color: AppTheme.primaryTeal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Intake Date (दर्ता मिति):',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                            Text(
                              NepaliLocalizationService.formatDualCalendarDate(
                                DateTime.now(),
                              ),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimaryLight,
                              ),
                            ),
                            if (camp != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${camp.name} • ${camp.venue}, Ward ${camp.ward}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryTeal,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          camp?.campCode ?? 'KTM01',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. LIVE DUPLICATE WARNING CARD
                if (state.duplicateResult.hasDuplicate)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.shade700,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber.shade900,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'DUPLICATE DATA DETECTED (दोहोरिएको रेकर्ड)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.duplicateResult.matchReasonEn ?? 'A patient with identical credentials already exists in this camp.',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF78350F),
                          ),
                        ),
                        if (state.duplicateResult.matchReasonNe != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            state.duplicateResult.matchReasonNe!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                // 3. Section 1: Patient Demographics Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              color: AppTheme.primaryTeal,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Patient Demographics (महिलाको विवरण)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _firstNameController,
                                decoration: const InputDecoration(
                                  labelText: 'First Name * (नाम)',
                                  hintText: 'e.g. Sita',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
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
                                decoration: const InputDecoration(
                                  labelText: 'Surname * (थर)',
                                  hintText: 'e.g. Sharma',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                onChanged: (val) {
                                  vm.updateField(surname: val);
                                  _triggerLiveDuplicateCheck();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ageController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Age * (उमेर)',
                                  hintText: 'Years',
                                  prefixIcon: Icon(Icons.cake_outlined),
                                ),
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
                              child: TextField(
                                controller: _wardController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Ward No * (वडा नं)',
                                  hintText: '01–35',
                                  prefixIcon: Icon(Icons.map_outlined),
                                ),
                                onChanged: (val) {
                                  vm.updateField(ward: val);
                                  _triggerLiveDuplicateCheck();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _districtController,
                                decoration: const InputDecoration(
                                  labelText: 'District (जिल्ला)',
                                  prefixIcon: Icon(
                                    Icons.location_city_outlined,
                                  ),
                                ),
                                onChanged: (val) {
                                  vm.updateField(district: val);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _municipalityController,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Municipality / Gaunpalika (गाउँपालिका)',
                                  prefixIcon: Icon(Icons.domain_outlined),
                                ),
                                onChanged: (val) {
                                  vm.updateField(municipality: val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Section 2: Family & Marital Profile Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.family_restroom_outlined,
                              color: AppTheme.primaryTeal,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Marital Profile (वैवाहिक स्थिति)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Marital Status Classification first
                        const Text(
                          'Marital Status Classification:',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children:
                              [
                                'married',
                                'unmarried',
                                'widow',
                                'divorced',
                              ].map((status) {
                                final isSelected =
                                    state.maritalStatus == status;
                                return ChoiceChip(
                                  label: Text(
                                    '${NepaliLocalizationService.translate(status)} ($status)',
                                  ),
                                  selected: isSelected,
                                  selectedColor: AppTheme.primaryTeal
                                      .withValues(alpha: 0.15),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? AppTheme.primaryTeal
                                        : const Color(0xFF334155),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 12.5,
                                  ),
                                  onSelected: (_) {
                                    if (status == 'unmarried') {
                                      _maritalAgeController.clear();
                                      vm.updateField(
                                        maritalStatus: status,
                                        relationshipType: 'Father',
                                        clearMaritalAge: true,
                                      );
                                    } else if (status == 'married') {
                                      vm.updateField(
                                        maritalStatus: status,
                                        relationshipType: 'Husband',
                                      );
                                    } else if (status == 'divorced') {
                                      vm.updateField(
                                        maritalStatus: status,
                                        relationshipType: 'Father',
                                      );
                                    } else {
                                      vm.updateField(maritalStatus: status);
                                    }
                                    setState(() {});
                                    _triggerLiveDuplicateCheck();
                                  },
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 16),

                        // Relative Name & Relationship Type (Dynamic based on marital status)
                        Builder(
                          builder: (context) {
                            final isUnmarried =
                                state.maritalStatus == 'unmarried';
                            final isWidow = state.maritalStatus == 'widow';
                            final isDivorced =
                                state.maritalStatus == 'divorced';

                            final String relativeLabel;
                            final String relativeHint;
                            final String relativeHelper;

                            if (isUnmarried) {
                              relativeLabel = "Father's / Guardian's Name * (बुबा वा संरक्षकको नाम)";
                              relativeHint = 'e.g. Bir Bahadur Tamang';
                              relativeHelper = 'Required for duplicate & identity check (unmarried)';
                            } else if (isWidow) {
                              relativeLabel = "Late Husband's / Father's Name * (दिवंगत श्रीमान वा बुबाको नाम)";
                              relativeHint = 'e.g. Late Dorje Tamang';
                              relativeHelper =
                                  'Required for duplicate check (widow)';
                            } else if (isDivorced) {
                              relativeLabel = "Father's / Guardian's Name * (बुबा वा संरक्षकको नाम)";
                              relativeHint = 'e.g. Bir Bahadur Tamang';
                              relativeHelper =
                                  'Required for duplicate check (divorced)';
                            } else {
                              relativeLabel =
                                  "Husband's Name * (श्रीमानको नाम)";
                              relativeHint = 'e.g. Dorje Tamang';
                              relativeHelper = isAdult
                                  ? 'Required for duplicate check (age ≥ 20)'
                                  : 'Required for duplicate check (age < 20)';
                            }

                            final List<DropdownMenuItem<String>> relationItems;
                            if (isUnmarried || isDivorced) {
                              relationItems = const [
                                DropdownMenuItem(
                                  value: 'Father',
                                  child: Text(
                                    'Father (बुबा)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'Mother',
                                  child: Text(
                                    'Mother (आमा)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'Guardian',
                                  child: Text(
                                    'Guardian (संरक्षक)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'Other',
                                  child: Text(
                                    'Other (अन्य)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ];
                            } else {
                              relationItems = const [
                                DropdownMenuItem(
                                  value: 'Husband',
                                  child: Text(
                                    'Husband (श्रीमान)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'Father',
                                  child: Text(
                                    'Father (बुबा)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'Guardian',
                                  child: Text(
                                    'Guardian (संरक्षक)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'M/SM/GP',
                                  child: Text(
                                    'M/SM/GP',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ];
                            }

                            final validValues = relationItems
                                .map((e) => e.value)
                                .toSet();
                            final selectedRelation =
                                validValues.contains(state.relationshipType)
                                ? state.relationshipType
                                : (isUnmarried || isDivorced
                                      ? 'Father'
                                      : 'Husband');

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: _spouseOrFatherController,
                                        decoration: InputDecoration(
                                          labelText: relativeLabel,
                                          hintText: relativeHint,
                                          prefixIcon: const Icon(
                                            Icons.people_alt_outlined,
                                          ),
                                          helperText: relativeHelper,
                                        ),
                                        onChanged: (val) {
                                          vm.updateField(
                                            spouseOrFatherName: val,
                                          );
                                          _triggerLiveDuplicateCheck();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 2,
                                      child: DropdownButtonFormField<String>(
                                        key: ValueKey(
                                          'relation_$selectedRelation',
                                        ),
                                        isExpanded: true,
                                        initialValue: selectedRelation,
                                        decoration: const InputDecoration(
                                          labelText: 'Relation (नाता)',
                                          prefixIcon: Icon(
                                            Icons.group_outlined,
                                          ),
                                        ),
                                        items: relationItems,
                                        onChanged: (val) {
                                          if (val != null) {
                                            vm.updateField(
                                              relationshipType: val,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Marriage Age (Hidden / info note for unmarried)
                                if (isUnmarried)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 18,
                                          color: Color(0xFF64748B),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Marriage Age is not applicable for unmarried patients (अविवाहित - विवाह उमेर लागू हुँदैन).',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF64748B),
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _maritalAgeController,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Marriage Age (विवाह उमेर)',
                                            hintText:
                                                'e.g. 18 (Years at marriage)',
                                            prefixIcon: Icon(
                                              Icons.history_edu_outlined,
                                            ),
                                            helperText: 'Assessing early marriage and obstetric risks',
                                          ),
                                          onChanged: (val) {
                                            final parsed = int.tryParse(val);
                                            vm.updateField(maritalAge: parsed);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Section 3: Contact Details Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.phone_in_talk_outlined,
                              color: AppTheme.primaryTeal,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Contact Information (सम्पर्क विवरण)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _mobileController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: "Woman's Mobile (मोबाइल नम्बर)",
                            hintText: '98XXXXXXXX',
                            prefixIcon: Icon(Icons.phone_android_rounded),
                          ),
                          onChanged: (val) {
                            vm.updateField(mobile: val);
                            _triggerLiveDuplicateCheck();
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _contactPersonController,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Secondary Contact (सम्पर्क व्यक्ति)',
                                  hintText: 'Son / Brother / Relative',
                                  prefixIcon: Icon(Icons.person_pin_outlined),
                                ),
                                onChanged: (val) {
                                  vm.updateField(contactPerson: val);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _contactMobileController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                decoration: const InputDecoration(
                                  labelText: 'Contact Mobile (सम्पर्क नम्बर)',
                                  hintText: '98XXXXXXXX',
                                  prefixIcon: Icon(
                                    Icons.contact_phone_outlined,
                                  ),
                                ),
                                onChanged: (val) {
                                  vm.updateField(contactMobile: val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 6. Section 4: Reasons for Visit Checkboxes
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.checklist_rounded,
                              color: AppTheme.primaryTeal,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Primary Reason for Visit (शिविरमा आउनुको मुख्य कारण)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select all presenting symptoms matching Yellow Form Page 1 checkboxes:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 550;
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: isWide ? 2 : 1,
                                    childAspectRatio: isWide ? 5.0 : 4.5,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: _reasonOptions.length,
                              itemBuilder: (context, index) {
                                final reason = _reasonOptions.keys.elementAt(index);
                                final label = _reasonOptions[reason]!;
                                final isChecked = state.selectedReasons
                                    .contains(reason);
                                return _buildReasonTile(
                                  reason,
                                  label,
                                  isChecked,
                                  () => vm.toggleReason(reason),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 7. Section 5: Clinical Consents
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          activeThumbColor: AppTheme.primaryTeal,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Consent for Treatment (उपचारको सहमति)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: const Text(
                            'Patient consents to medical examination and clinical treatment.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          value: state.consentTreatment,
                          onChanged: (val) =>
                              vm.updateField(consentTreatment: val),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          activeThumbColor: AppTheme.primaryTeal,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Consent to Store Medical Information',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: const Text(
                            'Patient consents to secure recording in the Gynocamp health database.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          value: state.consentStoreMedicalInfo,
                          onChanged: (val) =>
                              vm.updateField(consentStoreMedicalInfo: val),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                if (state.errorMessage != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerRose.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.dangerRose),
                    ),
                    child: Text(
                      state.errorMessage!,
                      style: const TextStyle(
                        color: AppTheme.dangerRose,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],

                // 8. Submit & Registration Action Bar
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      label: const Text('Clear'),
                      onPressed: _clearForm,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: state.isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded, size: 20),
                        label: Text(
                          state.isSubmitting ? 'Registering Patient...' : 'Register Patient & Start Clinical Form (Station 1 → 2)',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: state.isSubmitting || camp == null
                            ? null
                            : () async {
                                final scaffoldMessenger = ScaffoldMessenger.of(
                                  context,
                                );

                                if (!state.isValid) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(
                                            Icons.error_outline,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              state.validationError ?? 'Please complete all required fields properly.',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: Colors.red[700],
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 4),
                                    ),
                                  );
                                  return;
                                }

                                if (state.selectedReasons.isEmpty) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: const Row(
                                        children: [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Please select at least one primary reason for visit (शिविरमा आउनुको मुख्य कारण).',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: Colors.orange[800],
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }

                                final registered = await vm.submitRegistration(
                                  campId: camp.id,
                                  campCode: camp.campCode,
                                  staffUserId: user?.id ?? 'usr-field',
                                  deviceId: device?.deviceId ?? 'dev-field',
                                  tenantId: camp.tenantId.isNotEmpty
                                      ? camp.tenantId
                                      : (user?.tenantId ?? 'default_tenant'),
                                );

                                if (!mounted) return;

                                if (registered != null) {
                                  ref
                                      .read(campStateProvider.notifier)
                                      .loadCamps();
                                  ref
                                      .read(patientListProvider.notifier)
                                      .loadPatients(camp.id);

                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Registered: ${registered.fullName} (ID: ${registered.patientId})',
                                      ),
                                      backgroundColor: AppTheme.successGreen,
                                    ),
                                  );

                                  await _handlePostRegistrationSlip(
                                    registered,
                                    camp,
                                  );
                                }
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormStepBar(PatientRegistrationState state) {
    final steps = [
      _FormStep(label: 'Demographics', icon: Icons.person_outline_rounded, done: state.firstName.isNotEmpty && state.age != null),
      _FormStep(label: 'Family Profile', icon: Icons.family_restroom_outlined, done: state.spouseOrFatherName.isNotEmpty),
      _FormStep(label: 'Contact Info', icon: Icons.phone_in_talk_outlined, done: state.mobile.isNotEmpty),
      _FormStep(label: 'Visit Reasons', icon: Icons.checklist_rounded, done: state.selectedReasons.isNotEmpty),
      _FormStep(label: 'Consent', icon: Icons.verified_user_outlined, done: state.consentTreatment && state.consentStoreMedicalInfo),
    ];
    final completedCount = steps.where((s) => s.done).length;
    final progressFraction = completedCount / steps.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_turned_in_outlined, size: 16, color: AppTheme.primaryTeal),
              const SizedBox(width: 6),
              Text(
                'Form Completion ($completedCount / ${steps.length} sections)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              Text(
                '${(progressFraction * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressFraction,
              minHeight: 5,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryTeal),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: steps.asMap().entries.map((entry) {
              final step = entry.value;
              final isLast = entry.key == steps.length - 1;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: step.done
                                  ? AppTheme.primaryTeal
                                  : const Color(0xFFF1F5F9),
                              border: Border.all(
                                color: step.done ? AppTheme.primaryTeal : const Color(0xFFCBD5E1),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                step.done ? Icons.check_rounded : step.icon,
                                size: 14,
                                color: step.done ? Colors.white : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            step.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: step.done ? FontWeight.bold : FontWeight.normal,
                              color: step.done ? AppTheme.primaryTeal : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 16,
                        height: 1.5,
                        color: step.done ? AppTheme.primaryTeal : const Color(0xFFE2E8F0),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonTile(
    String reason,
    String displayLabel,
    bool isChecked,
    VoidCallback onToggle,
  ) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isChecked
              ? AppTheme.primaryTeal.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isChecked ? AppTheme.primaryTeal : const Color(0xFFE2E8F0),
            width: isChecked ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isChecked,
              onChanged: (_) => onToggle(),
              activeColor: AppTheme.primaryTeal,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                displayLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                  color: isChecked
                      ? AppTheme.primaryTeal
                      : const Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormStep {
  final String label;
  final IconData icon;
  final bool done;
  const _FormStep({required this.label, required this.icon, required this.done});
}
