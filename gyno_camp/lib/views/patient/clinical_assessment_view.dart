import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/clinical_constants.dart';
import '../../core/services/clinical_validation_service.dart';
import '../../core/services/nepali_localization_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/patient_model.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/clinical_assessment_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';

class ClinicalAssessmentView extends ConsumerStatefulWidget {
  final PatientModel patient;

  const ClinicalAssessmentView({super.key, required this.patient});

  @override
  ConsumerState<ClinicalAssessmentView> createState() => _ClinicalAssessmentViewState();
}

class _ClinicalAssessmentViewState extends ConsumerState<ClinicalAssessmentView> {
  // Controllers
  final _deliveriesController = TextEditingController();
  final _livingChildrenController = TextEditingController();
  final _abortionsController = TextEditingController();

  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _pulseController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _glucoseController = TextEditingController();
  final _ecgController = TextEditingController();

  final _pessarySizeController = TextEditingController();
  final _customMedController = TextEditingController();
  final _outtakeNotesController = TextEditingController();

  @override
  void dispose() {
    _deliveriesController.dispose();
    _livingChildrenController.dispose();
    _abortionsController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    _spo2Controller.dispose();
    _glucoseController.dispose();
    _ecgController.dispose();
    _pessarySizeController.dispose();
    _customMedController.dispose();
    _outtakeNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clinicalAssessmentProvider);
    final vm = ref.read(clinicalAssessmentProvider.notifier);
    final user = ref.watch(authStateProvider).currentUser;
    final device = ref.watch(deviceSecurityProvider).device;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Clinical Intake • ${widget.patient.fullName}'),
            Text(
              'ID: ${widget.patient.patientId} • Age: ${widget.patient.age} • Ward: ${widget.patient.ward}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Station Indicator Stepper Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStepTab(0, '1. Anamnesis', Icons.history_edu, state.currentStationIndex),
                  _buildStepTab(1, '2. Exam & POP', Icons.accessibility_new, state.currentStationIndex),
                  _buildStepTab(2, '3. Vitals & Lab', Icons.monitor_heart, state.currentStationIndex),
                  _buildStepTab(3, '4. Diagnoses', Icons.checklist, state.currentStationIndex),
                  _buildStepTab(4, '5. Treatment', Icons.medication, state.currentStationIndex),
                  _buildStepTab(5, '6. Outtake', Icons.assignment_turned_in, state.currentStationIndex),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // Main Station Form Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18.0),
              child: _buildStationContent(state, vm),
            ),
          ),

          // Bottom Station Navigation Toolbar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.borderLight)),
            ),
            child: Row(
              children: [
                if (state.currentStationIndex > 0)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Previous'),
                    onPressed: () => vm.previousStation(),
                  ),
                const Spacer(),
                if (state.currentStationIndex < 5)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next Station'),
                    onPressed: () => vm.nextStation(),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
                    icon: state.isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: const Text('Complete & Save Record'),
                    onPressed: state.isSaving
                        ? null
                        : () async {
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            final navigator = Navigator.of(context);

                            final saved = await vm.submitAssessment(
                              patientId: widget.patient.patientId,
                              campId: widget.patient.campId,
                              staffUserId: user?.id ?? 'usr-doc',
                              deviceId: device?.deviceId ?? 'dev-field',
                            );

                            if (!mounted) return;

                            if (saved != null) {
                              scaffoldMessenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Clinical Assessment successfully saved in local SQLite!'),
                                  backgroundColor: AppTheme.successGreen,
                                ),
                              );
                              navigator.pop();
                            }
                          },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTab(int index, String label, IconData icon, int currentIndex) {
    final isSelected = index == currentIndex;
    return InkWell(
      onTap: () => ref.read(clinicalAssessmentProvider.notifier).setStation(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryTeal : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : AppTheme.textPrimaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationContent(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    switch (state.currentStationIndex) {
      case 0:
        return _buildStation1Anamnesis(state, vm);
      case 1:
        return _buildStation2ExamAndPOP(state, vm);
      case 2:
        return _buildStation3VitalsAndLab(state, vm);
      case 3:
        return _buildStation4Diagnoses(state, vm);
      case 4:
        return _buildStation5Treatment(state, vm);
      case 5:
      default:
        return _buildStation6Outtake(state, vm);
    }
  }

  // --- 1. Anamnesis / Obstetric History ---
  Widget _buildStation1Anamnesis(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Obstetric History (सुत्केरी तथा गर्भ विवरण)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _deliveriesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Deliveries (सुत्केरी संख्या)'),
                onChanged: (val) => vm.setObstetricHistory(deliveries: int.tryParse(val)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _livingChildrenController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Living Children (जीवित बच्चा)'),
                onChanged: (val) => vm.setObstetricHistory(livingChildren: int.tryParse(val)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _abortionsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Abortions (गर्भपतन)'),
                onChanged: (val) => vm.setObstetricHistory(abortions: int.tryParse(val)),
              ),
            ),
          ],
        ),
        if (state.obstetricValidation.isError)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              state.obstetricValidation.messageEn!,
              style: const TextStyle(color: AppTheme.dangerRose, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        const SizedBox(height: 20),

        const Text('Chief Complaints Details (Yellow Form 9 Symptoms)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        _buildComplaintCard(
          title: 'Something hanging out (पाठेघर खस्ने समस्या)',
          hasDuration: true,
          options: ['previous pessary', 'previous surgery'],
          onUpdate: (data) => vm.updateComplaint('prolapse', data),
        ),
        const SizedBox(height: 10),

        _buildComplaintCard(
          title: 'Discharge / Itching (पानी बग्ने / चिलाउने)',
          hasDuration: true,
          options: ['white', 'yellow', 'green', 'grey', 'smelly'],
          onUpdate: (data) => vm.updateComplaint('discharge', data),
        ),
        const SizedBox(height: 10),

        _buildComplaintCard(
          title: 'Problems passing urine (पिसाब सम्बन्धी समस्या)',
          hasDuration: true,
          options: ['stress incontinence', 'urge incontinence', 'continuous flow'],
          onUpdate: (data) => vm.updateComplaint('urine', data),
        ),
        const SizedBox(height: 10),

        _buildComplaintCard(
          title: 'Menstrual problem (महिनावारी समस्या)',
          hasDuration: false,
          options: ['dysmenorrhoea', 'metrorrhagia', 'menorrhagia', 'postmenopausal bleeding'],
          onUpdate: (data) => vm.updateComplaint('menstrual', data),
        ),
      ],
    );
  }

  Widget _buildComplaintCard({
    required String title,
    required bool hasDuration,
    required List<String> options,
    required Function(Map<String, dynamic>) onUpdate,
  }) {
    String selectedDuration = '<1month';
    final List<String> selectedOptions = [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (hasDuration) ...[
              const SizedBox(height: 6),
              const Text('Since when (कहिलेदेखि):', style: TextStyle(fontSize: 11, color: Colors.grey)),
              Wrap(
                spacing: 6,
                children: ['< 1month', '< 1 year', '> 1 year', '> 5 years', '> 10 years'].map((d) {
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(d, style: const TextStyle(fontSize: 11)),
                    selected: selectedDuration == d,
                    onSelected: (val) {
                      selectedDuration = d;
                      onUpdate({'duration': selectedDuration, 'options': selectedOptions});
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: options.map((opt) {
                final isChecked = selectedOptions.contains(opt);
                return FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${NepaliLocalizationService.translate(opt)} ($opt)', style: const TextStyle(fontSize: 11)),
                  selected: isChecked,
                  onSelected: (val) {
                    if (val) {
                      selectedOptions.add(opt);
                    } else {
                      selectedOptions.remove(opt);
                    }
                    onUpdate({'duration': selectedDuration, 'options': selectedOptions});
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // --- 2. Physical Examination & POP Staging ---
  Widget _buildStation2ExamAndPOP(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Uterus Inside (पाठेघर भित्रै छ?)', style: TextStyle(fontWeight: FontWeight.bold)),
          value: state.uterusInside,
          onChanged: (val) => vm.updateExam(uterusInside: val),
        ),
        const SizedBox(height: 12),

        const Text('Pelvic Floor Muscle Tone (पेल्भिक मांसपेशीको अवस्था)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: ['normal', 'weak', 'hypertonic'].map((tone) {
            final isSelected = state.pelvicFloorTone == tone;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: ChoiceChip(
                  label: Center(child: Text('${NepaliLocalizationService.translate(tone)} ($tone)', style: const TextStyle(fontSize: 11))),
                  selected: isSelected,
                  onSelected: (_) => vm.updateExam(pelvicFloorTone: tone),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // POP STAGING BOX
        Card(
          color: AppTheme.primaryLight.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.primaryTeal),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'POP STAGING (Pelvic Organ Prolapse)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryDark),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryTeal,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Highest POP: Stage ${state.highestPopStage}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Anterior Wall (Stage 0 - 3)
                _buildPopStageSelector(
                  title: 'POP Anterior Wall (अगाडिको भित्ता):',
                  maxStage: 3,
                  currentStage: state.popAnteriorStage,
                  onSelect: (stg) => vm.setPopStages(anterior: stg),
                ),
                const SizedBox(height: 10),

                // Middle Part (Stage 0 - 4)
                _buildPopStageSelector(
                  title: 'POP Middle Part (बीचको भाग - Uterine):',
                  maxStage: 4,
                  currentStage: state.popMiddleStage,
                  onSelect: (stg) => vm.setPopStages(middle: stg),
                ),
                const SizedBox(height: 10),

                // Posterior Wall (Stage 0 - 3)
                _buildPopStageSelector(
                  title: 'POP Posterior Wall (पछाडिको भित्ता):',
                  maxStage: 3,
                  currentStage: state.popPosteriorStage,
                  onSelect: (stg) => vm.setPopStages(posterior: stg),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPopStageSelector({
    required String title,
    required int maxStage,
    required int currentStage,
    required Function(int) onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          children: List.generate(maxStage + 1, (index) {
            final isSelected = currentStage == index;
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text('Stage $index', style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (_) => onSelect(index),
              ),
            );
          }),
        ),
      ],
    );
  }

  // --- 3. Lab Tests & Numeric Vitals (Live Validation) ---
  Widget _buildStation3VitalsAndLab(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rapid Point-of-Care Tests (प्रयोगशाला जाँच)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: state.urineTest,
                decoration: const InputDecoration(labelText: 'Urine Test (पिसाब जाँच)'),
                items: const [
                  DropdownMenuItem(value: 'normal', child: Text('Normal (सामान्य)')),
                  DropdownMenuItem(value: 'pos', child: Text('Positive (संक्रमण देखियो)')),
                ],
                onChanged: (val) => vm.setVitals(urineTest: val),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: state.pregnancyTest,
                decoration: const InputDecoration(labelText: 'Pregnancy Test (गर्भावस्था)'),
                items: const [
                  DropdownMenuItem(value: 'neg', child: Text('Negative (नेगेटिभ)')),
                  DropdownMenuItem(value: 'pos', child: Text('Positive (पोजिटिभ)')),
                ],
                onChanged: (val) => vm.setVitals(pregnancyTest: val),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        const Text('Numeric Vital Signs (महत्वपूर्ण शारीरिक सूचकहरू)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Real-time validation checks for typos and abnormal health thresholds:', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),

        // Blood Pressure (Systolic / Diastolic)
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _systolicController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Systolic BP (सिस्टोलिक)',
                  suffixText: 'mmHg',
                  prefixIcon: _getValidationIcon(state.systolicValidation),
                ),
                onChanged: (val) => vm.setVitals(systolic: int.tryParse(val)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _diastolicController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Diastolic BP (डायस्टोलिक)',
                  suffixText: 'mmHg',
                  prefixIcon: _getValidationIcon(state.diastolicValidation),
                ),
                onChanged: (val) => vm.setVitals(diastolic: int.tryParse(val)),
              ),
            ),
          ],
        ),
        _buildValidationMessage(state.systolicValidation),
        _buildValidationMessage(state.diastolicValidation),
        const SizedBox(height: 12),

        // Pulse and Oxygen Saturation
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pulseController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Pulse (नाडी गति)',
                  suffixText: 'bpm',
                  prefixIcon: _getValidationIcon(state.pulseValidation),
                ),
                onChanged: (val) => vm.setVitals(pulse: int.tryParse(val)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _spo2Controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'SpO2 (अक्सिजन)',
                  suffixText: '%',
                  prefixIcon: _getValidationIcon(state.spo2Validation),
                ),
                onChanged: (val) => vm.setVitals(spo2: int.tryParse(val)),
              ),
            ),
          ],
        ),
        _buildValidationMessage(state.pulseValidation),
        _buildValidationMessage(state.spo2Validation),
        const SizedBox(height: 12),

        // Blood Glucose
        TextField(
          controller: _glucoseController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Blood Glucose (रक्त ग्लुकोज)',
            suffixText: 'mg/dL',
            prefixIcon: _getValidationIcon(state.glucoseValidation),
          ),
          onChanged: (val) => vm.setVitals(glucose: int.tryParse(val)),
        ),
        _buildValidationMessage(state.glucoseValidation),
      ],
    );
  }

  Widget _getValidationIcon(ValidationResult result) {
    if (result.isError) return const Icon(Icons.cancel, color: AppTheme.dangerRose);
    if (result.isWarning) return const Icon(Icons.warning, color: AppTheme.warningAmber);
    return const Icon(Icons.check_circle, color: AppTheme.successGreen);
  }

  Widget _buildValidationMessage(ValidationResult result) {
    if (result.isNormal || result.messageEn == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4.0, left: 4.0),
      child: Text(
        '${result.messageEn!} (${result.messageNe ?? ""})',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: result.isError ? AppTheme.dangerRose : AppTheme.warningAmber,
        ),
      ),
    );
  }

  // --- 4. Diagnoses (21 Standard Yellow Form Options) ---
  Widget _buildStation4Diagnoses(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Clinical Diagnoses (${state.selectedDiagnoses.length} selected)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text('Select all confirmed conditions from the Yellow Form standard list:', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: ClinicalConstants.defaultDiagnoses.map((diag) {
            final isSelected = state.selectedDiagnoses.contains(diag);
            return FilterChip(
              label: Text(
                '${NepaliLocalizationService.translate(diag)} ($diag)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedColor: AppTheme.primaryLight,
              checkmarkColor: AppTheme.primaryTeal,
              onSelected: (_) => vm.toggleDiagnosis(diag),
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- 5. Treatment & Prescriptions ---
  Widget _buildStation5Treatment(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Specialized Counseling (परामर्श)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: ['weak pelvic floor', 'POP', 'stress incontinence', 'urge incontinence', 'abdominal pain'].map((c) {
            final isSelected = state.selectedCounseling.contains(c);
            return FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(c, style: const TextStyle(fontSize: 11)),
              selected: isSelected,
              onSelected: (_) => vm.toggleCounseling(c),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),

        const Text('Ring Pessary Fitting (रिङ पेसरी)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: state.pessaryType,
                decoration: const InputDecoration(labelText: 'Pessary Type'),
                items: ['ring', 'ring with support', 'ring with knob'].map((t) {
                  return DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)));
                }).toList(),
                onChanged: (val) => vm.setPessary(type: val),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _pessarySizeController,
                decoration: const InputDecoration(labelText: 'Size (साइज mm)'),
                onChanged: (val) => vm.setPessary(size: val),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        const Text('Referral for Surgery (शल्यक्रिया सिफारिस)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: state.surgicalReferral,
          decoration: const InputDecoration(labelText: 'Referral Hospital'),
          items: ClinicalConstants.referralHospitals.map((h) {
            return DropdownMenuItem(value: h, child: Text(h));
          }).toList(),
          onChanged: (val) => vm.setSurgicalReferral(val),
        ),
        const SizedBox(height: 18),

        const Text('Medications Prescribed (औषधि वितरण)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: ClinicalConstants.defaultMedications.map((m) {
            final isSelected = state.selectedMedications.contains(m);
            return FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(m, style: const TextStyle(fontSize: 11)),
              selected: isSelected,
              onSelected: (_) => vm.toggleMedication(m),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customMedController,
          decoration: const InputDecoration(labelText: 'Other Medicines (अन्य औषधिहरू)'),
          onChanged: (val) => vm.setCustomMedication(val),
        ),
      ],
    );
  }

  // --- 6. Outtake & Follow-up ---
  Widget _buildStation6Outtake(ClinicalAssessmentState state, ClinicalAssessmentViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Follow-Up Plan (पुनः जाँच योजना)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: RadioGroup<bool>(
            groupValue: state.followUpNeeded,
            onChanged: (val) {
              if (val != null) vm.setOuttake(followUpNeeded: val);
            },
            child: Column(
              children: [
                const RadioListTile<bool>(
                  title: Text('Follow-up Needed (थप जाँच आवश्यक)'),
                  value: true,
                ),
                if (state.followUpNeeded) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: DropdownButtonFormField<String>(
                      initialValue: state.followUpDestination ?? 'Health Post',
                      decoration: const InputDecoration(labelText: 'Follow-up Center'),
                      items: const [
                        DropdownMenuItem(value: 'Health Post', child: Text('Local Health Post (स्वास्थ्य चौकी)')),
                        DropdownMenuItem(value: 'GynaeSupport Nurse', child: Text('GynaeSupport Nurse (गाइनोसपोर्ट नर्स)')),
                      ],
                      onChanged: (val) => vm.setOuttake(destination: val),
                    ),
                  ),
                ],
                const Divider(height: 1),
                const RadioListTile<bool>(
                  title: Text('No Follow-up Needed (थप जाँच आवश्यक छैन)'),
                  value: false,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        const Text('Clinical Notes / Referral Summary (अन्तिम टिप्पणी)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _outtakeNotesController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Enter clinical impressions, patient instructions, or surgical notes...',
          ),
          onChanged: (val) => vm.setOuttake(notes: val),
        ),
      ],
    );
  }
}
