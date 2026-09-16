import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/clinical_constants.dart';
import '../../core/services/nepali_localization_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/camp_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/patient_model.dart';

import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/device_security_viewmodel.dart';
import '../../viewmodels/master_lookup_viewmodel.dart';
import '../../viewmodels/patient_registration_viewmodel.dart';

class PatientFollowUpFormView extends ConsumerStatefulWidget {
  final PatientModel patient;
  final CampModel? camp;

  const PatientFollowUpFormView({
    super.key,
    required this.patient,
    this.camp,
  });

  @override
  ConsumerState<PatientFollowUpFormView> createState() => _PatientFollowUpFormViewState();
}

class _PatientFollowUpFormViewState extends ConsumerState<PatientFollowUpFormView> {
  final _formKey = GlobalKey<FormState>();

  // Prior visits history
  bool _isLoadingHistory = true;
  List<ClinicalVisitModel> _pastVisits = [];
  ClinicalVisitModel? _latestVisit;

  // Form Fields
  final TextEditingController _newIssuesController = TextEditingController();
  final TextEditingController _followUpNotesController = TextEditingController();
  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();
  final TextEditingController _pulseController = TextEditingController();
  final TextEditingController _spo2Controller = TextEditingController();
  final TextEditingController _glucoseController = TextEditingController();

  // Active / New Clinical Complaints
  final Set<String> _selectedComplaints = {};

  // POP Staging
  int _anteriorStage = 0;
  int _middleStage = 0;
  int _posteriorStage = 0;

  // Diagnoses
  final Set<String> _selectedDiagnoses = {};

  // Surgery
  bool _surgeryDone = false;
  String? _selectedSurgeryType;

  // Grouping Toggles
  bool _groupDiagnosesByCategory = true;
  bool _groupMedicationsByCategory = true;

  // Treatment / Follow-Up Outtake
  final Set<String> _selectedMedications = {};
  String? _pessaryType;
  String? _pessarySize;
  String? _followUpDestination;
  bool _followUpNeeded = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPatientHistory();
  }

  @override
  void dispose() {
    _newIssuesController.dispose();
    _followUpNotesController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    _spo2Controller.dispose();
    _glucoseController.dispose();
    super.dispose();
  }

  Future<void> _loadPatientHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final repo = ref.read(patientRepositoryProvider);
      final visits = await repo.getClinicalVisits(widget.patient.patientId, patientUuid: widget.patient.id);
      if (mounted) {
        setState(() {
          _pastVisits = visits;
          if (visits.isNotEmpty) {
            _latestVisit = visits.first;
            // Pre-seed known ongoing diagnoses and baseline values
            _selectedDiagnoses.addAll(_latestVisit!.diagnoses);
            _anteriorStage = _latestVisit!.popAnteriorStage;
            _middleStage = _latestVisit!.popMiddleStage;
            _posteriorStage = _latestVisit!.popPosteriorStage;
            _surgeryDone = _latestVisit!.surgeryDone;
            _selectedSurgeryType = _latestVisit!.surgeryType;
            if (_latestVisit!.systolicBp != null) {
              _systolicController.text = _latestVisit!.systolicBp.toString();
            }
            if (_latestVisit!.diastolicBp != null) {
              _diastolicController.text = _latestVisit!.diastolicBp.toString();
            }
            if (_latestVisit!.pulse != null) {
              _pulseController.text = _latestVisit!.pulse.toString();
            }
            if (_latestVisit!.spo2 != null) {
              _spo2Controller.text = _latestVisit!.spo2.toString();
            }
          }
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  int get _calculatedHighestPopStage {
    int highest = _anteriorStage;
    if (_middleStage > highest) highest = _middleStage;
    if (_posteriorStage > highest) highest = _posteriorStage;
    return highest;
  }

  Future<void> _submitFollowUp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final auth = ref.read(authStateProvider).currentUser;
    final deviceId = ref.read(deviceSecurityProvider).hardwareFingerprint;
    final repo = ref.read(patientRepositoryProvider);

    final complaintsMap = <String, dynamic>{
      'reasons': _selectedComplaints.toList(),
      'new_issues': _newIssuesController.text.trim().toUpperCase(),
    };

    final newVisit = ClinicalVisitModel(
      id: '', // Will be assigned UUID by repository
      patientId: widget.patient.patientId,
      campId: widget.camp?.id ?? widget.patient.campId,
      visitDate: DateTime.now(),
      deliveries: _latestVisit?.deliveries ?? 0,
      livingChildren: _latestVisit?.livingChildren ?? 0,
      abortions: _latestVisit?.abortions ?? 0,
      anamnesisComplaints: complaintsMap,
      popAnteriorStage: _anteriorStage,
      popMiddleStage: _middleStage,
      popPosteriorStage: _posteriorStage,
      highestPopStage: _calculatedHighestPopStage,
      systolicBp: int.tryParse(_systolicController.text.trim()),
      diastolicBp: int.tryParse(_diastolicController.text.trim()),
      pulse: int.tryParse(_pulseController.text.trim()),
      spo2: int.tryParse(_spo2Controller.text.trim()),
      glucose: int.tryParse(_glucoseController.text.trim()),
      diagnoses: _selectedDiagnoses.toList(),
      medications: _selectedMedications.toList(),
      pessaryType: _pessaryType,
      pessarySize: _pessarySize,
      followUpNeeded: _followUpNeeded,
      followUpDestination: _followUpDestination,
      outtakeNotes: _followUpNotesController.text.trim().toUpperCase(),
      isFollowUp: true,
      followUpNotes: _newIssuesController.text.trim().toUpperCase(),
      surgeryDone: _surgeryDone,
      surgeryType: _surgeryDone ? _selectedSurgeryType : null,
      createdAt: DateTime.now(),
      createdByUserId: auth?.id ?? 'usr-staff',
    );

    try {
      await repo.saveClinicalVisit(
        newVisit,
        createdByUserId: auth?.id ?? 'usr-staff',
        deviceId: deviceId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Follow-up visit record saved successfully!'),
            backgroundColor: AppTheme.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save follow-up record: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Follow-Up Visit Assessment', style: TextStyle(fontSize: 16)),
            Text(
              '${widget.patient.fullName} (${widget.patient.patientId})',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Mandatory Instruction Banner (Block Letters)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.primaryDark, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'INSTRUCTION: PLEASE FILL IN BLOCK LETTERS (सफा ठूला अक्षरमा भर्नुहोस्)',
                        style: TextStyle(
                          color: AppTheme.primaryDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. Patient Summary Card
              _buildPatientHeaderCard(),
              const SizedBox(height: 14),

              // 3. Chronological Visit History Timeline
              _buildVisitHistoryCard(),
              const SizedBox(height: 14),

              // Error feedback if any
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRose.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.dangerRose),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.dangerRose),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // 4. Section: New Clinical Complaints & Observations
              _buildComplaintsSection(),
              const SizedBox(height: 14),

              // 5. Section: Physical Vitals Check
              _buildVitalsSection(),
              const SizedBox(height: 14),

              // 6. Section: POP Re-Staging
              _buildPopStagingSection(),
              const SizedBox(height: 14),

              // 7. Section: Updated Diagnoses & Surgical Interventions
              _buildDiagnosesAndSurgerySection(),
              const SizedBox(height: 14),

              // 8. Section: Management & Outtake Notes
              _buildManagementSection(),
              const SizedBox(height: 24),

              // Save Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _isSaving ? 'Saving Record...' : 'Save Follow-Up Record (फलो-अप सुरक्षित गर्नुहोस्)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSaving ? null : _submitFollowUp,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientHeaderCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.12),
              child: Text(
                widget.patient.firstName.isNotEmpty ? widget.patient.firstName[0].toUpperCase() : 'P',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.patient.fullName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.patient.patientId,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Age: ${widget.patient.age}y • Ward: ${widget.patient.ward} • ${widget.patient.district}, ${widget.patient.province}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondaryLight),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitHistoryCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: _pastVisits.isNotEmpty,
        leading: const Icon(Icons.history_rounded, color: AppTheme.primaryTeal),
        title: Row(
          children: [
            const Text(
              'Chronological Visit History',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_pastVisits.length} visits',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
              ),
            ),
          ],
        ),
        subtitle: const Text('Track progression & newly recorded issues', style: TextStyle(fontSize: 11)),
        children: [
          if (_isLoadingHistory)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_pastVisits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No previous clinical visits found. This will be recorded as the initial follow-up.',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondaryLight),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _pastVisits.length,
              separatorBuilder: (_, _) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final visit = _pastVisits[index];
                final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(visit.visitDate);

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: index == 0 ? AppTheme.primaryLight.withValues(alpha: 0.3) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: index == 0 ? AppTheme.primaryTeal.withValues(alpha: 0.3) : Colors.grey.shade300,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                visit.isFollowUp ? Icons.replay_rounded : Icons.fiber_new_rounded,
                                size: 16,
                                color: visit.isFollowUp ? AppTheme.accentCyan : AppTheme.primaryTeal,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                visit.isFollowUp ? 'Follow-Up Visit' : 'Initial Assessment',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          Text(
                            dateStr,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'POP Stage: ${visit.highestPopStage} (A:${visit.popAnteriorStage} M:${visit.popMiddleStage} P:${visit.popPosteriorStage}) • BP: ${visit.systolicBp ?? "-"}/${visit.diastolicBp ?? "-"} mmHg',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      if (visit.diagnoses.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Diagnoses: ${visit.diagnoses.join(", ")}',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.primaryDark),
                        ),
                      ],
                      if (visit.surgeryDone) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Surgery Done: ${visit.surgeryType ?? "Yes"}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                        ),
                      ],
                      if (visit.followUpNotes != null && visit.followUpNotes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Follow-up Notes / New Issues: ${visit.followUpNotes}',
                          style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black87),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildComplaintsSection() {
    const complaintsList = [
      {'key': 'something hanging out', 'label': 'Something hanging out (आङ खस्ने)'},
      {'key': 'discharge and or itching', 'label': 'Discharge / Itching (स्राव / चिलाउने)'},
      {'key': 'problems passing urine', 'label': 'Urinary complaint (पिसाब सम्बन्धी)'},
      {'key': 'problems passing stool', 'label': 'Stool complaint (दिसा सम्बन्धी)'},
      {'key': 'menstrual problem', 'label': 'Menstrual issue (महिनावारी समस्या)'},
      {'key': 'infertility', 'label': 'Infertility (निःसन्तान)'},
      {'key': 'pain', 'label': 'Pelvic / abdominal pain (तल्लो पेट दुखाइ)'},
      {'key': 'checkup', 'label': 'Routine follow-up checkup (नियमित जाँच)'},
    ];

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Follow-Up Complaints & New Issues (फलो-अप समस्याहरू)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select any ongoing symptoms or newly emerged clinical issues',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondaryLight),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: complaintsList.map((c) {
                final isSelected = _selectedComplaints.contains(c['key']);
                return FilterChip(
                  label: Text(c['label']!),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryLight,
                  checkmarkColor: AppTheme.primaryTeal,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedComplaints.add(c['key']!);
                      } else {
                        _selectedComplaints.remove(c['key']);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _newIssuesController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [const UpperCaseTextFormatter()],
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'NEW ISSUES / OBSERVATIONS (नयाँ देखिएका समस्या तथा कैफियत) [BLOCK LETTERS]',
                hintText: 'e.g. RING PESSARY DISPLACEMENT, PERSISTENT DISCHARGE',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalsSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '2. Physical Vitals Check (शारीरिक जाँच)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _systolicController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Systolic BP',
                      suffixText: 'mmHg',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _diastolicController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Diastolic BP',
                      suffixText: 'mmHg',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _pulseController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Pulse Rate',
                      suffixText: 'bpm',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _spo2Controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'SpO2',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _glucoseController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Blood Glucose',
                      suffixText: 'mg/dL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopStagingSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '3. POP Re-Staging (आङ खस्ने जाँच)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _calculatedHighestPopStage >= 2
                        ? AppTheme.warningAmber.withValues(alpha: 0.15)
                        : AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _calculatedHighestPopStage >= 2 ? AppTheme.warningAmber : AppTheme.primaryTeal,
                    ),
                  ),
                  child: Text(
                    'Overall: Stage $_calculatedHighestPopStage',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _calculatedHighestPopStage >= 2 ? Colors.brown : AppTheme.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStageSelector('Anterior Compartment (Cystocele)', _anteriorStage, [0, 1, 2, 3], (val) {
              setState(() => _anteriorStage = val);
            }),
            const SizedBox(height: 8),
            _buildStageSelector('Middle Compartment (Uterine/Apex)', _middleStage, [0, 1, 2, 3, 4], (val) {
              setState(() => _middleStage = val);
            }),
            const SizedBox(height: 8),
            _buildStageSelector('Posterior Compartment (Rectocele)', _posteriorStage, [0, 1, 2, 3], (val) {
              setState(() => _posteriorStage = val);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStageSelector(String title, int current, List<int> allowed, ValueChanged<int> onSelect) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: allowed.map((stage) {
            final isSelected = current == stage;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ChoiceChip(
                label: Text('S$stage'),
                selected: isSelected,
                selectedColor: AppTheme.primaryTeal,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onSelected: (_) => onSelect(stage),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDiagnosesAndSurgerySection() {
    final lookupState = ref.watch(masterLookupProvider);
    final activeDiagItems = lookupState.activeDiagnoses;
    final List<String> diagnosesList = activeDiagItems.isNotEmpty
        ? activeDiagItems.map((d) => d.labelEn).toList()
        : ClinicalConstants.defaultDiagnoses;

    final Map<String, String> itemToCategory = {};
    for (final d in activeDiagItems) {
      if (d.subCategory != null && d.subCategory!.isNotEmpty) {
        itemToCategory[d.labelEn] = d.subCategory!;
      }
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '4. Diagnoses & Surgical Evaluation (${_selectedDiagnoses.length} selected)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    side: BorderSide(color: AppTheme.primaryTeal.withValues(alpha: 0.5)),
                  ),
                  icon: Icon(
                    _groupDiagnosesByCategory ? Icons.category_rounded : Icons.view_list_rounded,
                    size: 14,
                    color: AppTheme.primaryTeal,
                  ),
                  label: Text(
                    _groupDiagnosesByCategory ? 'Grouped' : 'Flat List',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                  ),
                  onPressed: () => setState(() => _groupDiagnosesByCategory = !_groupDiagnosesByCategory),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!_groupDiagnosesByCategory)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: diagnosesList.map((d) {
                  final isSelected = _selectedDiagnoses.contains(d);
                  return FilterChip(
                    label: Text('${NepaliLocalizationService.translate(d)} ($d)', style: const TextStyle(fontSize: 11.5)),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryLight,
                    checkmarkColor: AppTheme.primaryTeal,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedDiagnoses.add(d);
                        } else {
                          _selectedDiagnoses.remove(d);
                        }
                      });
                    },
                  );
                }).toList(),
              )
            else
              Column(
                children: ClinicalConstants.diagnosisCategories.map((category) {
                  final itemsInCategory = diagnosesList.where((d) {
                    final cat = itemToCategory[d] ?? ClinicalConstants.diagnosisCategoryMap[d] ?? 'General / Other (सामान्य)';
                    return cat == category;
                  }).toList();

                  if (itemsInCategory.isEmpty) return const SizedBox.shrink();
                  final selectedCount = itemsInCategory.where((d) => _selectedDiagnoses.contains(d)).length;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: selectedCount > 0 ? AppTheme.primaryTeal.withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
                          width: selectedCount > 0 ? 1.4 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        key: PageStorageKey('followup_diag_$category'),
                      initiallyExpanded: selectedCount > 0 || category.contains('Prolapse'),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      dense: true,
                      leading: Icon(
                        Icons.folder_open_rounded,
                        size: 16,
                        color: selectedCount > 0 ? AppTheme.primaryTeal : Colors.blueGrey,
                      ),
                      title: Text(
                        category,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: selectedCount > 0 ? AppTheme.primaryTeal : const Color(0xFF1E293B),
                        ),
                      ),
                      trailing: selectedCount > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryTeal,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$selectedCount',
                                style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            )
                          : null,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: itemsInCategory.map((d) {
                              final isSelected = _selectedDiagnoses.contains(d);
                              return FilterChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  '${NepaliLocalizationService.translate(d)} ($d)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryLight,
                                checkmarkColor: AppTheme.primaryTeal,
                                onSelected: (val) {
                                  setState(() {
                                    if (val) {
                                      _selectedDiagnoses.add(d);
                                    } else {
                                      _selectedDiagnoses.remove(d);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Surgery Performed (शल्यक्रिया भएको हो?)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              subtitle: const Text(
                'Indicate if surgical intervention was performed prior to or during follow-up',
                style: TextStyle(fontSize: 11),
              ),
              value: _surgeryDone,
              activeThumbColor: AppTheme.primaryTeal,
              onChanged: (val) {
                setState(() {
                  _surgeryDone = val;
                  if (!_surgeryDone) _selectedSurgeryType = null;
                });
              },
            ),
            if (_surgeryDone) ...[
              const SizedBox(height: 8),
              const Text(
                'Surgical Route / Procedure Type (शल्यक्रियाको प्रकार):',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  'Open surgery',
                  'Laparoscopy',
                  'Vaginal route',
                ].map((type) {
                  final isSelected = _selectedSurgeryType == type;
                  return ChoiceChip(
                    label: Text(type),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                    onSelected: (selected) {
                      setState(() {
                        _selectedSurgeryType = selected ? type : null;
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManagementSection() {
    final lookupState = ref.watch(masterLookupProvider);
    final activeMedItems = lookupState.activeMedicines;
    final List<String> medicinesList = activeMedItems.isNotEmpty
        ? activeMedItems.map((m) => m.labelEn).toList()
        : ClinicalConstants.defaultMedications;

    final Map<String, String> medToCategory = {};
    for (final m in activeMedItems) {
      if (m.subCategory != null && m.subCategory!.isNotEmpty) {
        medToCategory[m.labelEn] = m.subCategory!;
      }
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '5. Prescription & Follow-up Destination (${_selectedMedications.length} selected)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    side: BorderSide(color: AppTheme.primaryTeal.withValues(alpha: 0.5)),
                  ),
                  icon: Icon(
                    _groupMedicationsByCategory ? Icons.category_rounded : Icons.view_list_rounded,
                    size: 14,
                    color: AppTheme.primaryTeal,
                  ),
                  label: Text(
                    _groupMedicationsByCategory ? 'Grouped' : 'Flat List',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                  ),
                  onPressed: () => setState(() => _groupMedicationsByCategory = !_groupMedicationsByCategory),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!_groupMedicationsByCategory)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: medicinesList.map((med) {
                  final isSelected = _selectedMedications.contains(med);
                  return FilterChip(
                    label: Text(med, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedMedications.add(med);
                        } else {
                          _selectedMedications.remove(med);
                        }
                      });
                    },
                  );
                }).toList(),
              )
            else
              Column(
                children: ClinicalConstants.medicationCategories.map((category) {
                  final itemsInCategory = medicinesList.where((m) {
                    final cat = medToCategory[m] ?? ClinicalConstants.medicationCategoryMap[m] ?? 'Other / Custom (अन्य औषधिहरू)';
                    return cat == category;
                  }).toList();

                  if (itemsInCategory.isEmpty) return const SizedBox.shrink();
                  final selectedCount = itemsInCategory.where((m) => _selectedMedications.contains(m)).length;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: selectedCount > 0 ? AppTheme.primaryTeal.withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
                          width: selectedCount > 0 ? 1.4 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        key: PageStorageKey('followup_med_$category'),
                      initiallyExpanded: selectedCount > 0,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      dense: true,
                      leading: Icon(
                        Icons.medication_outlined,
                        size: 16,
                        color: selectedCount > 0 ? AppTheme.primaryTeal : Colors.blueGrey,
                      ),
                      title: Text(
                        category,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: selectedCount > 0 ? AppTheme.primaryTeal : const Color(0xFF1E293B),
                        ),
                      ),
                      trailing: selectedCount > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryTeal,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$selectedCount',
                                style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            )
                          : null,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: itemsInCategory.map((med) {
                              final isSelected = _selectedMedications.contains(med);
                              return FilterChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(med, style: const TextStyle(fontSize: 11)),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryTeal.withValues(alpha: 0.2),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedMedications.add(med);
                                    } else {
                                      _selectedMedications.remove(med);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _pessaryType,
                    decoration: const InputDecoration(
                      labelText: 'Pessary Fitted / Type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      ...['ring', 'ring with support', 'ring with knob'].map((p) => DropdownMenuItem(value: p, child: Text(p))),
                    ],
                    onChanged: (val) => setState(() => _pessaryType = val),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _pessarySize,
                    decoration: const InputDecoration(
                      labelText: 'Pessary Size (साइज mm)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => _pessarySize = val.isEmpty ? null : val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Further Follow-Up Needed? (थप फलो-अप आवश्यक छ?)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              subtitle: const Text(
                'Check if patient requires ongoing review or scheduled clinic revisit',
                style: TextStyle(fontSize: 11),
              ),
              value: _followUpNeeded,
              activeThumbColor: AppTheme.primaryTeal,
              onChanged: (val) => setState(() => _followUpNeeded = val),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _followUpDestination,
              decoration: const InputDecoration(
                labelText: 'Follow-Up Destination / Hospital',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Local Health Post / Camp')),
                ...ClinicalConstants.referralHospitals.map((h) => DropdownMenuItem(value: h, child: Text(h))),
              ],
              onChanged: (val) => setState(() => _followUpDestination = val),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _followUpNotesController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [const UpperCaseTextFormatter()],
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'FINAL FOLLOW-UP NOTES / COUNSELING [BLOCK LETTERS]',
                hintText: 'e.g. RING PESSARY CLEANED AND REINSERTED, PATIENT ADVISED REGULAR HYGIENE',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
