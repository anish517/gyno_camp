import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/services/pdf_report_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/patient_model.dart';
import 'patient_registration_view.dart';

class ClinicalHistoryPanel extends StatefulWidget {
  final PatientModel patient;
  final CampModel? camp;
  final String orgName;
  final dynamic repo;

  const ClinicalHistoryPanel({super.key, required this.patient, required this.camp, required this.orgName, required this.repo});

  @override
  State<ClinicalHistoryPanel> createState() => _ClinicalHistoryPanelState();
}

class _ClinicalHistoryPanelState extends State<ClinicalHistoryPanel> {
  late Future<List<ClinicalVisitModel>> _visitsFuture;
  late PatientModel _patient;
  final Set<int> _dlIdx = {};
  bool _dlDossier = false;
  int _mobileTabIndex = 1; // 0 = Profile & Obstetric Overview, 1 = Clinical Timeline & Encounters

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _visitsFuture = widget.repo.getClinicalVisits(_patient.patientId, patientUuid: _patient.id);
  }

  Future<void> _dlSlip(ClinicalVisitModel v, int i) async {
    setState(() => _dlIdx.add(i));
    try {
      final bytes = await PdfReportService().generateFollowUpEncounterSlipPdf(
        patient: _patient, visit: v, camp: widget.camp, organizationName: widget.orgName,
      );
      final ds = DateFormat('yyyyMMdd').format(v.visitDate);
      final result = await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes, filename: 'EncounterSlip_${_patient.patientId}_$ds.pdf', mimeType: 'application/pdf',
      );
      if (mounted) {
        FileDownloadHelper.showDownloadFeedback(context, result);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.dangerRose));
    } finally {
      if (mounted) setState(() => _dlIdx.remove(i));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _patient;
    final fmt = DateFormat('dd MMM yyyy, HH:mm');
    final sd = DateFormat('dd MMM yyyy');
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;

        return Column(children: [
          _topBar(p, isMobile: isMobile),
          Expanded(child: FutureBuilder<List<ClinicalVisitModel>>(
            future: _visitsFuture,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final visits = snap.data ?? [];

              if (isMobile) {
                return Column(
                  children: [
                    // Mobile segmented switcher: Overview vs Visits
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      color: const Color(0xFFF1F5F9),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _mobileTabIndex = 0),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _mobileTabIndex == 0 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: _mobileTabIndex == 0
                                      ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    'Patient Profile & History',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _mobileTabIndex == 0 ? FontWeight.bold : FontWeight.w600,
                                      color: _mobileTabIndex == 0 ? AppTheme.primaryTeal : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _mobileTabIndex = 1),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _mobileTabIndex == 1 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: _mobileTabIndex == 1
                                      ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    'Encounters (${visits.length})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _mobileTabIndex == 1 ? FontWeight.bold : FontWeight.w600,
                                      color: _mobileTabIndex == 1 ? AppTheme.primaryTeal : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _mobileTabIndex == 0
                          ? _sidebar(p, visits, sd, isMobile: true)
                          : _timeline(visits, fmt, isMobile: true),
                    ),
                  ],
                );
              }

              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 240, child: _sidebar(p, visits, sd, isMobile: false)),
                Expanded(child: _timeline(visits, fmt, isMobile: false)),
              ]);
            },
          )),
          _bottomBar(isMobile: isMobile),
        ]);
      },
    );
  }

  Widget _topBar(PatientModel p, {bool isMobile = false}) => Container(
    padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.only(topLeft: Radius.circular(20)),
      boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))],
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppTheme.primaryTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.history_edu_rounded, color: AppTheme.primaryTeal, size: 24),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    p.fullName,
                    style: TextStyle(fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    p.patientId,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF64748B)),
                    const SizedBox(width: 2),
                    Text(
                      '${p.district.isNotEmpty ? p.district : "District N/A"}, Ward ${p.ward}',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const Text('•', style: TextStyle(color: Color(0xFFCBD5E1))),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cake_outlined, size: 12, color: Color(0xFF64748B)),
                    const SizedBox(width: 2),
                    Text(
                      'Age ${p.age}',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                if (p.maritalStatus.isNotEmpty) ...[
                  const Text('•', style: TextStyle(color: Color(0xFFCBD5E1))),
                  Text(
                    p.maritalStatus,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      const SizedBox(width: 6),
      if (isMobile)
        IconButton(
          tooltip: 'Edit Page 1',
          style: IconButton.styleFrom(
            foregroundColor: AppTheme.primaryTeal,
            side: const BorderSide(color: AppTheme.primaryTeal),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.all(8),
          ),
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          onPressed: () async {
            final updated = await Navigator.push<PatientModel?>(
              context,
              MaterialPageRoute(
                builder: (_) => PatientRegistrationView(patientToEdit: _patient),
              ),
            );
            if (updated != null && mounted) {
              setState(() {
                _patient = updated;
              });
            }
          },
        )
      else
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryTeal,
            side: const BorderSide(color: AppTheme.primaryTeal),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.edit_note_rounded, size: 16),
          label: const Text('Edit Page 1', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          onPressed: () async {
            final updated = await Navigator.push<PatientModel?>(
              context,
              MaterialPageRoute(
                builder: (_) => PatientRegistrationView(patientToEdit: _patient),
              ),
            );
            if (updated != null && mounted) {
              setState(() {
                _patient = updated;
              });
            }
          },
        ),
      const SizedBox(width: 6),
      IconButton(
        icon: const Icon(Icons.close_rounded, size: 20),
        style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9)),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ]),
  );

  Widget _sidebar(PatientModel p, List<ClinicalVisitModel> visits, DateFormat sd, {bool isMobile = false}) => Container(
    margin: EdgeInsets.all(isMobile ? 12 : 14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8)]),
    child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 60, height: 60, decoration: BoxDecoration(color: AppTheme.primaryTeal.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Center(child: Text(p.firstName.isNotEmpty ? p.firstName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal))))),
      const SizedBox(height: 10),
      Center(child: Text(p.fullName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)))),
      Center(child: Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppTheme.primaryTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
        child: Text(p.patientId, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal)))),
      const SizedBox(height: 12), const Divider(color: Color(0xFFE2E8F0)), const SizedBox(height: 6),
      _infoRow(Icons.cake_rounded, 'Age', '${p.age} yrs'),
      _infoRow(Icons.favorite_rounded, 'Marital', p.maritalStatus),
      _infoRow(Icons.location_on_rounded, 'Address', 'Ward ${p.ward}, ${p.municipality}'),
      _infoRow(Icons.map_rounded, 'District', p.district),
      if (p.province.isNotEmpty) _infoRow(Icons.flag_outlined, 'Province', p.province),
      _infoRow(Icons.phone_rounded, 'Mobile', p.mobile.isNotEmpty ? p.mobile : 'N/A'),
      if (p.spouseOrFatherName?.isNotEmpty == true)
        _infoRow(Icons.person_rounded, p.age < 20 ? 'Father' : 'Husband', p.spouseOrFatherName!),
      if (p.contactPerson?.isNotEmpty == true)
        _infoRow(Icons.contact_phone_outlined, 'Contact', p.contactPerson!),
      if (p.contactMobile?.isNotEmpty == true)
        _infoRow(Icons.phone_iphone_rounded, 'Contact No.', p.contactMobile!),
      if (p.maritalAge != null)
        _infoRow(Icons.event_outlined, 'Age at Marriage', '${p.maritalAge} yrs'),
      const SizedBox(height: 10), const Divider(color: Color(0xFFE2E8F0)), const SizedBox(height: 6),
      Row(
        children: [
          const Text('Obstetric History (प्रसूति विवरण)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
          const SizedBox(width: 4),
          Tooltip(
            message: 'P: Parity/Deliveries (सुत्केरी संख्या)\nL: Living Children (जीवित सन्तान)\nA: Abortions/Losses (गर्भपतन)',
            child: const Icon(Icons.info_outline_rounded, size: 12, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
      const SizedBox(height: 5),
      // Obstetrics from most recent visit if available
      FutureBuilder<List<ClinicalVisitModel>>(
        future: _visitsFuture,
        builder: (ctx, snap) {
          if (!snap.hasData || snap.data!.isEmpty) {
            return const Text('No obstetric data', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)));
          }
          // Use initial visit (first) for obstetric history
          final v = snap.data!.first;
          if (v.deliveries == null && v.livingChildren == null && v.abortions == null) {
            return const Text('Not recorded', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)));
          }
          return Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              _obsBadge('Deliveries (P)', v.deliveries?.toString() ?? '?', AppTheme.brandPurpleLight, AppTheme.brandPurple, tooltip: 'Parity / Total Deliveries (सुत्केरी संख्या)'),
              _obsBadge('Living (L)', v.livingChildren?.toString() ?? '?', const Color(0xFFF0FFF4), const Color(0xFF16A34A), tooltip: 'Living Children (जीवित सन्तान)'),
              _obsBadge('Losses (A)', v.abortions?.toString() ?? '?', const Color(0xFFFFF7ED), const Color(0xFFEA580C), tooltip: 'Abortions / Miscarriages (गर्भपतन वा खेर गएको)'),
            ],
          );
        },
      ),
      const SizedBox(height: 10), const Divider(color: Color(0xFFE2E8F0)), const SizedBox(height: 6),
      const Text('Reasons for Visit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
      const SizedBox(height: 4),
      p.reasonsForVisit.isEmpty
        ? const Text('None recorded', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))
        : Wrap(spacing: 4, runSpacing: 4, children: p.reasonsForVisit.map((r) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: AppTheme.brandPurpleLight, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.brandPurpleBorder)),
            child: Text(r, style: const TextStyle(fontSize: 10, color: AppTheme.primaryDark)))).toList()),
      const SizedBox(height: 10), const Divider(color: Color(0xFFE2E8F0)), const SizedBox(height: 4),
      _consentRow('Consent to Treatment', p.consentTreatment),
      const SizedBox(height: 4),
      _consentRow('Consent to Store Data', p.consentStoreMedicalInfo),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.brandPurpleLight, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.brandPurpleBorder)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _statBadge('${visits.length}', 'Visits'),
          _statBadge('${visits.where((v) => v.isFollowUp).length}', 'FU'),
          if (visits.isNotEmpty) _statBadge(sd.format(visits.first.visitDate), '1st'),
        ])),
    ])),
  );

  Widget _timeline(List<ClinicalVisitModel> visits, DateFormat fmt, {bool isMobile = false}) {
    if (visits.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        const Text('No clinical encounters recorded yet', style: TextStyle(fontSize: 16, color: Color(0xFF94A3B8))),
        const SizedBox(height: 6),
        const Text('Complete Station 1-6 or a Follow-Up Form to log visits.', style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1))),
      ]));
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(isMobile ? 12 : 0, 14, 14, 24),
      itemCount: visits.length,
      itemBuilder: (ctx, i) => _card(visits[i], i, fmt, isMobile: isMobile),
    );
  }

  Widget _card(ClinicalVisitModel v, int i, DateFormat fmt, {bool isMobile = false}) {
    final isF = v.isFollowUp;
    final isDl = _dlIdx.contains(i);
    final ac = isF ? AppTheme.brandMagenta : AppTheme.brandPurple;
    final bg = isF ? const Color(0xFFFDF2F8) : AppTheme.brandPurpleLight;

    // BP classification matching PDF slip (only classified when measurements exist)
    String? bpStatus;
    Color bpColor = AppTheme.textSecondaryLight;
    if (v.systolicBp != null && v.diastolicBp != null) {
      final s = v.systolicBp!;
      final d = v.diastolicBp!;
      if (s >= 160 || d >= 100) {
        bpStatus = 'HTN 2 (Critical)';
        bpColor = AppTheme.dangerRose;
      } else if (s >= 140 || d >= 90) {
        bpStatus = 'HTN 1 (Elevated)';
        bpColor = Colors.orange.shade800;
      } else if (s >= 120) {
        bpStatus = 'Pre-HTN';
        bpColor = Colors.amber.shade800;
      } else {
        bpStatus = 'Normal';
        bpColor = AppTheme.successGreen;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ac.withValues(alpha: 0.25), width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Header Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: ac.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Icon(isF ? Icons.replay_circle_filled_rounded : Icons.local_hospital_rounded, size: 17, color: ac),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isF ? 'Follow-Up Visit #$i' : 'Primary Camp Examination (Initial)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: ac),
                      ),
                      Text(fmt.format(v.visitDate), style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ac,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: isDl
                      ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_rounded, size: 14),
                  label: Text(isDl ? 'Downloading...' : (isMobile ? 'Slip' : 'Download Slip'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: isDl ? null : () => _dlSlip(v, i),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Obstetric History & Pelvic Floor Exam (Station 2)
                if (v.deliveries != null || v.livingChildren != null || v.abortions != null || v.cervixRemarks != null || v.vaginaRemarks != null || !v.uterusInside) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Obstetric & Pelvic Floor Examination (प्रसूति तथा श्रोणी जाँच):',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (v.deliveries != null || v.livingChildren != null || v.abortions != null) ...[
                              _obsBadge('Deliveries (P)', v.deliveries?.toString() ?? '?', AppTheme.brandPurpleLight, AppTheme.brandPurple, tooltip: 'Parity / Total Deliveries (सुत्केरी संख्या)'),
                              _obsBadge('Living (L)', v.livingChildren?.toString() ?? '?', const Color(0xFFF0FFF4), const Color(0xFF16A34A), tooltip: 'Living Children (जीवित सन्तान)'),
                              _obsBadge('Losses (A)', v.abortions?.toString() ?? '?', const Color(0xFFFFF7ED), const Color(0xFFEA580C), tooltip: 'Abortions / Miscarriages (गर्भपतन)'),
                            ],
                            _tb('Tone: ${v.pelvicFloorTone.toUpperCase()}', AppTheme.primaryTeal),
                            _tb(
                              v.uterusInside ? 'Uterus: Inside' : 'Uterus: Prolapsed',
                              v.uterusInside ? AppTheme.successGreen : AppTheme.dangerRose,
                            ),
                            if (v.cervixRemarks?.isNotEmpty == true)
                              _tb('Cervix: ${v.cervixRemarks}', const Color(0xFF64748B)),
                            if (v.vaginaRemarks?.isNotEmpty == true)
                              _tb('Vagina: ${v.vaginaRemarks}', const Color(0xFF64748B)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // 2. Vitals & Screening Labs (Station 3)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Clinical Vitals & Screening Labs (स्वास्थ्य सूचक):',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                          ),
                          if (bpStatus != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: bpColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: bpColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                'BP: $bpStatus',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: bpColor),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          _vc('BP', '${v.systolicBp ?? "-"}/${v.diastolicBp ?? "-"} mmHg'),
                          if (v.pulse != null) _vc('Pulse', '${v.pulse} bpm'),
                          if (v.spo2 != null) _vc('SpO2', '${v.spo2}%'),
                          if (v.glucose != null) _vc('Glucose', '${v.glucose} mg/dL'),
                          if (v.urineTest?.isNotEmpty == true) _vc('Urine', v.urineTest!.toUpperCase()),
                          if (v.pregnancyTest?.isNotEmpty == true) _vc('Pregnancy', v.pregnancyTest!.toUpperCase()),
                          if (v.ecgNotes?.isNotEmpty == true) _vc('ECG', v.ecgNotes!),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // 3. Baden-Walker POP Staging (Station 4)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Baden-Walker POP:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(width: 4),
                    if (v.highestPopStage == 0) ...[
                      _pb('', 'Normal (No Prolapse)', isNormal: true),
                      _pb('Ant', 'St 0'),
                      _pb('Mid', 'St 0'),
                      _pb('Post', 'St 0'),
                    ] else ...[
                      _pb('Highest', 'St ${v.highestPopStage}', ip: v.highestPopStage == 2, ic: v.highestPopStage >= 3),
                      _pb('Ant', 'St ${v.popAnteriorStage}'),
                      _pb('Mid', 'St ${v.popMiddleStage}'),
                      _pb('Post', 'St ${v.popPosteriorStage}'),
                    ],
                  ],
                ),

                // 4. Confirmed Diagnoses (Station 5)
                if (v.diagnoses.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Diagnoses: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: v.diagnoses.map((d) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3)),
                            ),
                            child: Text(d, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.primaryDark)),
                          )).toList(),
                        ),
                      ),
                    ],
                  ),
                ],

                // 5. Prescriptions & Treatments (Station 5)
                if (v.medications.isNotEmpty || v.customMedication?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Prescriptions: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            ...v.medications.map((m) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F9FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF0891B2).withValues(alpha: 0.3)),
                              ),
                              child: Text(m, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF0C4A6E))),
                            )),
                            if (v.customMedication?.isNotEmpty == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                                ),
                                child: Text('Rx: ${v.customMedication}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF92400E))),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                // Interventions: Pessary, Surgery, Referral, Counseling
                if (v.pessarySize?.isNotEmpty == true || v.surgeryDone || v.surgicalReferral?.isNotEmpty == true || v.counseling.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      if (v.pessarySize?.isNotEmpty == true)
                        _tb('Pessary: ${v.pessaryType ?? "Ring"} Sz ${v.pessarySize}', AppTheme.primaryTeal),
                      if (v.surgeryDone)
                        _tb('Surgery: ${v.surgeryType ?? "Done"}', AppTheme.successGreen),
                      if (v.surgicalReferral?.isNotEmpty == true)
                        _tb('Referral: ${v.surgicalReferral}', AppTheme.dangerRose),
                      if (v.counseling.isNotEmpty)
                        _tb('Counseling: ${v.counseling.join(", ")}', const Color(0xFF0284C7)),
                    ],
                  ),
                ],

                // 6. Continuity of Care & Referral notes (Station 6)
                if (v.followUpNeeded || v.followUpDestination?.isNotEmpty == true || v.followUpNotes?.isNotEmpty == true || v.outtakeNotes?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              v.followUpNeeded ? 'Follow-Up Required: YES' : 'Follow-Up: Routine',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: v.followUpNeeded ? AppTheme.dangerRose : const Color(0xFF475569),
                              ),
                            ),
                            if (v.followUpDestination?.isNotEmpty == true) ...[
                              const SizedBox(width: 8),
                              Text(
                                '• Center: ${v.followUpDestination}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
                              ),
                            ],
                          ],
                        ),
                        if (v.followUpNotes?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text('Clinical Notes: ${v.followUpNotes}', style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Color(0xFF334155))),
                        ],
                        if (v.outtakeNotes?.isNotEmpty == true && v.outtakeNotes != v.followUpNotes) ...[
                          const SizedBox(height: 4),
                          Text('Attending Notes: ${v.outtakeNotes}', style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Color(0xFF334155))),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar({bool isMobile = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: 10),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, -2))]),
      child: FutureBuilder<List<ClinicalVisitModel>>(
        future: _visitsFuture,
        builder: (ctx, snap) {
          final visits = snap.data ?? [];
          final summaryMetadata = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.folder_shared_outlined, size: 15, color: AppTheme.primaryDark),
              ),
              const SizedBox(width: 6),
              Text(
                '${visits.length} Encounter${visits.length == 1 ? "" : "s"}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          );

          final closeBtn = OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Close'),
          );

          Widget? dossierBtn;
          if (visits.isNotEmpty) {
            dossierBtn = ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _dlDossier
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded, size: 15),
              label: Text(_dlDossier ? 'Generating...' : (isMobile ? 'Full Dossier (PDF)' : 'Full Clinical Dossier (PDF)'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: _dlDossier
                  ? null
                  : () async {
                      setState(() => _dlDossier = true);
                      try {
                        final bytes = await PdfReportService().generateIndividualPatientPdf(
                          patient: widget.patient,
                          visit: visits.last,
                          allVisits: visits,
                          camp: widget.camp,
                          organizationName: widget.orgName,
                        );
                        final result = await FileDownloadHelper.saveAndDownloadFile(
                          bytes: bytes,
                          filename: 'Dossier_${widget.patient.patientId}.pdf',
                          mimeType: 'application/pdf',
                        );
                        if (mounted) {
                          FileDownloadHelper.showDownloadFeedback(context, result);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.dangerRose),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _dlDossier = false);
                      }
                    },
            );
          }

          if (isMobile) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    summaryMetadata,
                    closeBtn,
                  ],
                ),
                if (dossierBtn != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: dossierBtn,
                  ),
                ],
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              summaryMetadata,
              Row(
                children: [
                  closeBtn,
                  if (dossierBtn != null) ...[
                    const SizedBox(width: 10),
                    dossierBtn,
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String lbl, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 12, color: const Color(0xFF94A3B8)), const SizedBox(width: 5),
      Expanded(child: RichText(text: TextSpan(style: const TextStyle(fontSize: 11, color: Color(0xFF334155)), children: [
        TextSpan(text: '$lbl: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569))),
        TextSpan(text: val),
      ]))),
    ]),
  );

  Widget _consentRow(String lbl, bool ok) => Row(children: [
    Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 13, color: ok ? AppTheme.successGreen : AppTheme.dangerRose),
    const SizedBox(width: 5), Expanded(child: Text(lbl, style: const TextStyle(fontSize: 10.5))),
  ]);

  Widget _statBadge(String val, String lbl) => Column(children: [
    Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal)),
    Text(lbl, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
  ]);

  Widget _vc(String lbl, String val) => RichText(text: TextSpan(style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)), children: [
    TextSpan(text: '$lbl: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155))),
    TextSpan(text: val, style: const TextStyle(fontWeight: FontWeight.w600)),
  ]));

  Widget _pb(String lbl, String val, {bool ip = false, bool ic = false, bool isNormal = false}) {
    final bg = ic
        ? const Color(0xFFFFE4E6)
        : ip
            ? const Color(0xFFFEF3C7)
            : isNormal
                ? const Color(0xFFF0FDF4)
                : const Color(0xFFF1F5F9);
    final fg = ic
        ? AppTheme.dangerRose
        : ip
            ? const Color(0xFF92400E)
            : isNormal
                ? const Color(0xFF166534)
                : const Color(0xFF334155);
    final bd = ic
        ? AppTheme.dangerRose
        : ip
            ? const Color(0xFFF59E0B)
            : isNormal
                ? const Color(0xFF86EFAC)
                : const Color(0xFFCBD5E1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: Border.all(color: bd, width: 0.8)),
      child: Text(lbl.isEmpty ? val : '$lbl: $val', style: TextStyle(fontSize: 10, fontWeight: (ip || ic || isNormal) ? FontWeight.bold : FontWeight.w600, color: fg)),
    );
  }

  Widget _tb(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.4))),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
  );

  Widget _obsBadge(String label, String value, Color bg, Color fg, {String? tooltip}) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5), border: Border.all(color: fg.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.85))),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: fg)),
      ]),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: badge);
    }
    return badge;
  }
}
