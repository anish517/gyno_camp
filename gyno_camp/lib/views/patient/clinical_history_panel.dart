import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/file_download_helper.dart';
import '../../core/services/pdf_report_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/patient_model.dart';


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
  final Set<int> _dlIdx = {};
  bool _dlDossier = false;
  bool _dlForm = false; // loading state for registration form download

  @override
  void initState() {
    super.initState();
    _visitsFuture = widget.repo.getClinicalVisits(widget.patient.patientId, patientUuid: widget.patient.id);
  }

  Future<void> _dlSlip(ClinicalVisitModel v, int i) async {
    setState(() => _dlIdx.add(i));
    try {
      final bytes = await PdfReportService().generateFollowUpEncounterSlipPdf(
        patient: widget.patient, visit: v, camp: widget.camp, organizationName: widget.orgName,
      );
      final ds = DateFormat('yyyyMMdd').format(v.visitDate);
      await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes, filename: 'EncounterSlip_${widget.patient.patientId}_$ds.pdf', mimeType: 'application/pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Slip downloaded for ${DateFormat("dd MMM yyyy").format(v.visitDate)}'),
          backgroundColor: AppTheme.successGreen, behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.dangerRose));
    } finally {
      if (mounted) setState(() => _dlIdx.remove(i));
    }
  }

  /// Downloads the block-letter registration form (Yellow Form) with patient data.
  /// Same form as generated after manual registration — for re-printing from history.
  Future<void> _dlRegistrationForm() async {
    setState(() => _dlForm = true);
    try {
      final bytes = await PdfReportService().generatePatientRegistrationFormPdf(
        patient: widget.patient,
        camp: widget.camp,
        organizationName: widget.orgName,
      );
      await FileDownloadHelper.saveAndDownloadFile(
        bytes: bytes,
        filename: 'RegistrationForm_${widget.patient.patientId}.pdf',
        mimeType: 'application/pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Registration form downloaded: RegistrationForm_${widget.patient.patientId}.pdf'),
          backgroundColor: AppTheme.successGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.dangerRose));
    } finally {
      if (mounted) setState(() => _dlForm = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    final fmt = DateFormat('dd MMM yyyy, HH:mm');
    final sd = DateFormat('dd MMM yyyy');
    return Column(children: [
      _topBar(p),
      Expanded(child: FutureBuilder<List<ClinicalVisitModel>>(
        future: _visitsFuture,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final visits = snap.data ?? [];
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 228, child: _sidebar(p, visits, sd)),
            Expanded(child: _timeline(visits, fmt)),
          ]);
        },
      )),
      _bottomBar(),
    ]);
  }

  Widget _topBar(PatientModel p) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(20)), boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))]),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.primaryTeal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.history_edu_rounded, color: AppTheme.primaryTeal, size: 26)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        Text('${p.patientId} \u2022 ${p.district} Ward ${p.ward} \u2022 Age ${p.age}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
      ])),
      IconButton(icon: const Icon(Icons.close_rounded), style: IconButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9)), onPressed: () => Navigator.of(context).pop()),
    ]),
  );

  Widget _sidebar(PatientModel p, List<ClinicalVisitModel> visits, DateFormat sd) => Container(
    margin: const EdgeInsets.all(14),
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
      const Text('Obstetric History (P/L/A)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
      const SizedBox(height: 4),
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
          return Row(children: [
            _obsBadge('P', v.deliveries?.toString() ?? '?', const Color(0xFFF0FDFA), AppTheme.primaryTeal),
            const SizedBox(width: 4),
            _obsBadge('L', v.livingChildren?.toString() ?? '?', const Color(0xFFF0FFF4), const Color(0xFF16A34A)),
            const SizedBox(width: 4),
            _obsBadge('A', v.abortions?.toString() ?? '?', const Color(0xFFFFF7ED), const Color(0xFFEA580C)),
          ]);
        },
      ),
      const SizedBox(height: 10), const Divider(color: Color(0xFFE2E8F0)), const SizedBox(height: 6),
      const Text('Reasons for Visit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
      const SizedBox(height: 4),
      p.reasonsForVisit.isEmpty
        ? const Text('None recorded', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))
        : Wrap(spacing: 4, runSpacing: 4, children: p.reasonsForVisit.map((r) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFF0FDFA), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3))),
            child: Text(r, style: const TextStyle(fontSize: 10, color: AppTheme.primaryDark)))).toList()),
      const SizedBox(height: 10), const Divider(color: Color(0xFFE2E8F0)), const SizedBox(height: 4),
      _consentRow('Consent to Treatment', p.consentTreatment),
      const SizedBox(height: 4),
      _consentRow('Consent to Store Data', p.consentStoreMedicalInfo),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF0FDFA), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _statBadge('${visits.length}', 'Visits'),
          _statBadge('${visits.where((v) => v.isFollowUp).length}', 'FU'),
          if (visits.isNotEmpty) _statBadge(sd.format(visits.first.visitDate), '1st'),
        ])),
    ])),
  );

  Widget _timeline(List<ClinicalVisitModel> visits, DateFormat fmt) {
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
      padding: const EdgeInsets.fromLTRB(0, 14, 14, 24),
      itemCount: visits.length,
      itemBuilder: (ctx, i) => _card(visits[i], i, fmt),
    );
  }

  Widget _card(ClinicalVisitModel v, int i, DateFormat fmt) {
    final isF = v.isFollowUp;
    final isDl = _dlIdx.contains(i);
    final ac = isF ? const Color(0xFF0891B2) : AppTheme.primaryTeal;
    final bg = isF ? const Color(0xFFECFEFF) : const Color(0xFFF0FDFA);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: ac.withValues(alpha: 0.25), width: 1.2), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))]),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: ac.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(isF ? Icons.replay_circle_filled_rounded : Icons.local_hospital_rounded, size: 17, color: ac)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isF ? 'Follow-Up Visit #$i' : 'Initial Examination', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: ac)),
              Text(fmt.format(v.visitDate), style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ])),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: ac, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
              icon: isDl ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download_rounded, size: 14),
              label: Text(isDl ? 'Downloading...' : 'Download Slip', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: isDl ? null : () => _dlSlip(v, i),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Wrap(spacing: 14, runSpacing: 4, children: [
              _vc('BP', '${v.systolicBp ?? "-"}/${v.diastolicBp ?? "-"} mmHg'),
              if (v.pulse != null) _vc('Pulse', '${v.pulse} bpm'),
              if (v.spo2 != null) _vc('SpO2', '${v.spo2}%'),
              if (v.glucose != null) _vc('Glucose', '${v.glucose} mg/dL'),
              if (v.urineTest?.isNotEmpty == true) _vc('Urine', v.urineTest!),
            ])),
          const SizedBox(height: 8),
          Row(children: [
            const Text('POP:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
            const SizedBox(width: 6),
            _pb('Highest', 'St ${v.highestPopStage}', ip: true, ic: v.highestPopStage >= 3),
            const SizedBox(width: 4), _pb('Ant', 'St ${v.popAnteriorStage}'),
            const SizedBox(width: 4), _pb('Mid', 'St ${v.popMiddleStage}'),
            const SizedBox(width: 4), _pb('Post', 'St ${v.popPosteriorStage}'),
          ]),
          if (v.diagnoses.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Obstetric summary inline in visit card
            if (v.deliveries != null || v.livingChildren != null || v.abortions != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Text('Obstetrics: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                  _obsBadge('P', v.deliveries?.toString() ?? '?', const Color(0xFFF0FDFA), AppTheme.primaryTeal),
                  const SizedBox(width: 3),
                  _obsBadge('L', v.livingChildren?.toString() ?? '?', const Color(0xFFF0FFF4), const Color(0xFF16A34A)),
                  const SizedBox(width: 3),
                  _obsBadge('A', v.abortions?.toString() ?? '?', const Color(0xFFFFF7ED), const Color(0xFFEA580C)),
                ]),
              ),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Diagnoses: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
              Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: v.diagnoses.map((d) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.primaryLight.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4), border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.3))),
                child: Text(d, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.primaryDark)))).toList())),
            ]),
          ],
          if (v.medications.isNotEmpty) ...[
            const SizedBox(height: 5),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Meds: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
              Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: v.medications.map((m) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF0891B2).withValues(alpha: 0.3))),
                child: Text(m, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF0C4A6E))))).toList())),
            ]),
          ],
          if (v.pessarySize?.isNotEmpty == true || v.surgeryDone || v.surgicalReferral?.isNotEmpty == true) ...[
            const SizedBox(height: 5),
            Wrap(spacing: 6, runSpacing: 5, children: [
              if (v.pessarySize?.isNotEmpty == true) _tb('Pessary: ${v.pessaryType ?? "Ring"} Sz ${v.pessarySize}', AppTheme.primaryTeal),
              if (v.surgeryDone) _tb('Surgery: ${v.surgeryType ?? "Done"}', AppTheme.successGreen),
              if (v.surgicalReferral?.isNotEmpty == true) _tb('Referral: ${v.surgicalReferral}', AppTheme.dangerRose),
            ]),
          ],
          if (v.followUpNotes?.isNotEmpty == true || v.outtakeNotes?.isNotEmpty == true) ...[
            const SizedBox(height: 7),
            Container(width: double.infinity, padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(7)),
              child: Text('Notes: ${v.followUpNotes?.isNotEmpty == true ? v.followUpNotes! : v.outtakeNotes!}', style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Color(0xFF334155)))),
          ],
        ])),
      ]),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, -2))]),
      child: FutureBuilder<List<ClinicalVisitModel>>(
        future: _visitsFuture,
        builder: (ctx, snap) {
          final visits = snap.data ?? [];
          return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            // Download filled block-letter Registration Form (Yellow Form)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryTeal,
                side: const BorderSide(color: AppTheme.primaryTeal),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _dlForm
                  ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryTeal))
                  : const Icon(Icons.article_outlined, size: 16),
              label: Text(_dlForm ? 'Downloading...' : 'Registration Form', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: _dlForm || _dlDossier ? null : _dlRegistrationForm,
            ),
            const SizedBox(width: 8),
            // Download Full Clinical Dossier (most recent visit)
            if (visits.isNotEmpty) ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              icon: _dlDossier ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: Text(_dlDossier ? 'Generating...' : 'Full Clinical Dossier (PDF)'),
              onPressed: _dlDossier ? null : () async {
                setState(() => _dlDossier = true);
                try {
                  // Use visits.last for most recent encounter data
                  final bytes = await PdfReportService().generateIndividualPatientPdf(patient: widget.patient, visit: visits.last, allVisits: visits, camp: widget.camp, organizationName: widget.orgName);
                  await FileDownloadHelper.saveAndDownloadFile(bytes: bytes, filename: 'Dossier_${widget.patient.patientId}.pdf', mimeType: 'application/pdf');
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full dossier downloaded!'), backgroundColor: AppTheme.successGreen, behavior: SnackBarBehavior.floating));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.dangerRose));
                } finally {
                  if (mounted) setState(() => _dlDossier = false);
                }
              },
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ]);
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

  Widget _pb(String lbl, String val, {bool ip = false, bool ic = false}) {
    final bg = ic ? const Color(0xFFFFE4E6) : ip ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9);
    final fg = ic ? AppTheme.dangerRose : ip ? const Color(0xFF92400E) : const Color(0xFF334155);
    final bd = ic ? AppTheme.dangerRose : ip ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: Border.all(color: bd, width: 0.8)), child: Text('$lbl: $val', style: TextStyle(fontSize: 10, fontWeight: ip ? FontWeight.bold : FontWeight.w600, color: fg)));
  }

  Widget _tb(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.4))),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
  );

  Widget _obsBadge(String label, String value, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5), border: Border.all(color: fg.withValues(alpha: 0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: fg.withValues(alpha: 0.7))),
      const SizedBox(width: 3),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
    ]),
  );
}
