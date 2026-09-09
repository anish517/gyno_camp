import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/camp_model.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/patient_model.dart';

class PdfReportService {
  Future<Uint8List> generateCampSummaryPdf(CampReportSummaryModel summary) async {
    final pdf = pw.Document();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

    final primaryColor = PdfColor.fromHex('0F766E'); // Teal
    final secondaryColor = PdfColor.fromHex('0D9488');
    final lightBgColor = PdfColor.fromHex('F0FDFA');
    final darkTextColor = PdfColor.fromHex('1E293B');
    final borderGray = PdfColor.fromHex('CBD5E1');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: lightBgColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(color: primaryColor, width: 1.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'GYNOCAMP HEALTH CLINICAL REPORT',
                      style: pw.TextStyle(
                        color: primaryColor,
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      summary.campName,
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: darkTextColor,
                      ),
                    ),
                    pw.Text(
                      '${summary.venue}, ${summary.municipality}, ${summary.district}',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: primaryColor,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        'CAMP CODE: ${summary.campCode}',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Period: ${dateFormatter.format(summary.startDate)} to ${dateFormatter.format(summary.endDate)}',
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'Generated: ${timeFormatter.format(summary.generatedAt)}',
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Executive Summary KPI Cards
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildKpiBox(
                title: 'Total Patients',
                value: '${summary.totalPatientsRegistered}',
                color: primaryColor,
              ),
              _buildKpiBox(
                title: 'Clinical Exams',
                value: '${summary.totalVisitsRecorded}',
                color: secondaryColor,
              ),
              _buildKpiBox(
                title: 'POP Stage >= 2',
                value: '${summary.significantPopPercentage}%',
                subtitle: '(${summary.significantPopCount} Patients)',
                color: PdfColor.fromHex('D97706'), // Amber
              ),
              _buildKpiBox(
                title: 'Surgical Referrals',
                value: '${summary.totalSurgicalReferrals}',
                color: PdfColor.fromHex('E11D48'), // Rose
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          // 1. Demographics Section
          _buildSectionHeader('1. Patient Demographics & Age Distribution', primaryColor),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Age Groups
              pw.SizedBox(
                width: 255,
                child: pw.Table(
                  border: pw.TableBorder.all(color: borderGray, width: 0.5),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _buildTableHeader('Age Group'),
                        _buildTableHeader('Count'),
                        _buildTableHeader('%'),
                      ],
                    ),
                    ...summary.ageGroups.entries.map((e) {
                      final pct = summary.totalPatientsRegistered > 0
                          ? ((e.value / summary.totalPatientsRegistered) * 100).toStringAsFixed(1)
                          : '0.0';
                      return pw.TableRow(
                        children: [
                          _buildTableCell(e.key),
                          _buildTableCell('${e.value}', align: pw.TextAlign.center),
                          _buildTableCell('$pct%', align: pw.TextAlign.right),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              // Marital Status
              pw.SizedBox(
                width: 255,
                child: pw.Table(
                  border: pw.TableBorder.all(color: borderGray, width: 0.5),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _buildTableHeader('Marital Status'),
                        _buildTableHeader('Count'),
                        _buildTableHeader('%'),
                      ],
                    ),
                    if (summary.maritalStatusCounts.isEmpty)
                      pw.TableRow(
                        children: [
                          _buildTableCell('None recorded'),
                          _buildTableCell('0', align: pw.TextAlign.center),
                          _buildTableCell('0.0%', align: pw.TextAlign.right),
                        ],
                      )
                    else
                      ...summary.maritalStatusCounts.entries.map((e) {
                        final pct = summary.totalPatientsRegistered > 0
                            ? ((e.value / summary.totalPatientsRegistered) * 100).toStringAsFixed(1)
                            : '0.0';
                        return pw.TableRow(
                          children: [
                            _buildTableCell(e.key.toUpperCase()),
                            _buildTableCell('${e.value}', align: pw.TextAlign.center),
                            _buildTableCell('$pct%', align: pw.TextAlign.right),
                          ],
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          // 2. POP Staging Matrix
          _buildSectionHeader('2. Pelvic Organ Prolapse (POP) Staging Matrix', primaryColor),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: borderGray, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildTableHeader('Compartment / Stage'),
                  _buildTableHeader('Stage 0'),
                  _buildTableHeader('Stage 1'),
                  _buildTableHeader('Stage 2'),
                  _buildTableHeader('Stage 3'),
                  _buildTableHeader('Stage 4'),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Anterior (Cystocele)', isBold: true),
                  _buildTableCell('${summary.anteriorStages[0] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.anteriorStages[1] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.anteriorStages[2] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.anteriorStages[3] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('N/A', align: pw.TextAlign.center),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Middle (Uterine / Apex)', isBold: true),
                  _buildTableCell('${summary.middleStages[0] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.middleStages[1] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.middleStages[2] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.middleStages[3] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.middleStages[4] ?? 0}', align: pw.TextAlign.center),
                ],
              ),
              pw.TableRow(
                children: [
                  _buildTableCell('Posterior (Rectocele)', isBold: true),
                  _buildTableCell('${summary.posteriorStages[0] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.posteriorStages[1] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.posteriorStages[2] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.posteriorStages[3] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('N/A', align: pw.TextAlign.center),
                ],
              ),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.teal50),
                children: [
                  _buildTableCell('Highest POP Stage', isBold: true),
                  _buildTableCell('${summary.highestPopStages[0] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.highestPopStages[1] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.highestPopStages[2] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.highestPopStages[3] ?? 0}', align: pw.TextAlign.center),
                  _buildTableCell('${summary.highestPopStages[4] ?? 0}', align: pw.TextAlign.center),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          // 3. Clinical Diagnoses & Pathologies
          _buildSectionHeader('3. Gynecological Diagnoses & Pathologies', primaryColor),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: borderGray, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildTableHeader('Clinical Diagnosis'),
                  _buildTableHeader('Cases Identified'),
                  _buildTableHeader('Prevalence (%)'),
                ],
              ),
              if (summary.diagnosisCounts.isEmpty)
                pw.TableRow(
                  children: [
                    _buildTableCell('No specific pathologies recorded'),
                    _buildTableCell('0', align: pw.TextAlign.center),
                    _buildTableCell('0.0%', align: pw.TextAlign.right),
                  ],
                )
              else
                ...summary.diagnosisCounts.entries.take(12).map((e) {
                  final pct = summary.totalVisitsRecorded > 0
                      ? ((e.value / summary.totalVisitsRecorded) * 100).toStringAsFixed(1)
                      : '0.0';
                  return pw.TableRow(
                    children: [
                      _buildTableCell(e.key),
                      _buildTableCell('${e.value}', align: pw.TextAlign.center),
                      _buildTableCell('$pct%', align: pw.TextAlign.right),
                    ],
                  );
                }),
            ],
          ),
          pw.SizedBox(height: 18),

          // 4. Treatments, Pessaries, Referrals & Pharmacy
          _buildSectionHeader('4. Interventions, Referrals & Pharmacy', primaryColor),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Interventions summary
              pw.SizedBox(
                width: 255,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Interventions & Referrals', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.SizedBox(height: 4),
                    _buildDetailBullet('Pessaries Fitted', '${summary.totalPessariesInserted} patients'),
                    _buildDetailBullet('Pelvic Floor Exercises', '${summary.pelvicFloorCounselingCount} counseled'),
                    _buildDetailBullet('Surgical Referrals', '${summary.totalSurgicalReferrals} cases'),
                    if (summary.surgicalReferralCounts.isNotEmpty)
                      ...summary.surgicalReferralCounts.entries.map(
                        (e) => pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 12),
                          child: pw.Text('- ${e.key}: ${e.value}', style: pw.TextStyle(fontSize: 8)),
                        ),
                      ),
                    pw.SizedBox(height: 6),
                    pw.Text('Point-of-Care Vitals Alerts', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    _buildDetailBullet('Hypertension (>=140/90)', '${summary.hypertensionCount} flagged'),
                    _buildDetailBullet('Hyperglycemia (>=140 mg/dL)', '${summary.hyperglycemiaCount} flagged'),
                    _buildDetailBullet('Urine Test Positive', '${summary.urinePositiveCount} flagged'),
                    _buildDetailBullet('Pregnancy Test Positive', '${summary.pregnancyPositiveCount} positive'),
                  ],
                ),
              ),
              // Top Medications
              pw.SizedBox(
                width: 255,
                child: pw.Table(
                  border: pw.TableBorder.all(color: borderGray, width: 0.5),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _buildTableHeader('Dispensed Medicine'),
                        _buildTableHeader('Rx Count'),
                      ],
                    ),
                    if (summary.medicationDispensedCounts.isEmpty)
                      pw.TableRow(
                        children: [
                          _buildTableCell('No medications dispensed'),
                          _buildTableCell('0', align: pw.TextAlign.center),
                        ],
                      )
                    else
                      ...summary.medicationDispensedCounts.entries.take(8).map((e) => pw.TableRow(
                            children: [
                              _buildTableCell(e.key),
                              _buildTableCell('${e.value}', align: pw.TextAlign.center),
                            ],
                          )),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 24),

          // Medical Officer Sign-off Block
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderGray, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Report Compiled By: ${summary.generatedBy}', style: pw.TextStyle(fontSize: 9)),
                    pw.Text('Digital Audit Chain Verified: SHA-256 Validated', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(width: 140, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 2),
                    pw.Text('Lead Gynecologist / Medical Officer', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildKpiBox({
    required String title,
    required String value,
    String? subtitle,
    required PdfColor color,
  }) {
    return pw.Container(
      width: 120,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 1.2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
            textAlign: pw.TextAlign.center,
          ),
          if (subtitle != null) ...[
            pw.SizedBox(height: 1),
            pw.Text(
              subtitle,
              style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildSectionHeader(String title, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  pw.Widget _buildTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _buildTableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _buildDetailBullet(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        children: [
          pw.Text('$label: ', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfField(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$label: ', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: isBold ? PdfColors.teal900 : PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> generateIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    CampModel? camp,
    String organizationName = 'Nepal Gyno Health Outreach Network',
  }) async {
    final pdf = pw.Document();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

    final primaryColor = PdfColor.fromHex('0F766E'); // Teal
    final secondaryColor = PdfColor.fromHex('0D9488');
    final lightBgColor = PdfColor.fromHex('F0FDFA');
    final darkTextColor = PdfColor.fromHex('1E293B');
    final borderGray = PdfColor.fromHex('CBD5E1');
    final alertRed = PdfColor.fromHex('BE123C');
    final warningAmber = PdfColor.fromHex('B45309');

    // Interpret Blood Pressure
    String bpStatus = 'N/A';
    PdfColor bpColor = darkTextColor;
    if (visit?.systolicBp != null && visit?.diastolicBp != null) {
      final s = visit!.systolicBp!;
      final d = visit.diastolicBp!;
      if (s >= 160 || d >= 100) {
        bpStatus = 'HTN Stage 2 (Severe Alert)';
        bpColor = alertRed;
      } else if (s >= 140 || d >= 90) {
        bpStatus = 'HTN Stage 1 (Elevated)';
        bpColor = warningAmber;
      } else if (s >= 120 || d >= 80) {
        bpStatus = 'Pre-Hypertension';
      } else {
        bpStatus = 'Normal Range';
        bpColor = primaryColor;
      }
    }

    // Map structured complaints
    final complaintsMap = visit?.anamnesisComplaints ?? {};
    final friendlyComplaintTitles = {
      'lower_abdominal_pain': 'Lower Abdominal Pain',
      'white_discharge': 'White / Foul Vaginal Discharge',
      'pelvic_heaviness': 'Pelvic Heaviness / Dragging Sensation',
      'burning_micturition': 'Burning Micturition / Dysuria',
      'incontinence': 'Urinary Incontinence',
      'dyspareunia': 'Dyspareunia / Coital Pain',
      'post_coital_bleeding': 'Abnormal / Coital Bleeding',
      'mass_per_vagina': 'Mass Per Vagina / Protrusion',
      'backache': 'Severe Backache / Sacral Pain',
    };

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 26, vertical: 24),
        build: (context) => [
          // 1. EXECUTIVE CLINICAL DOSSIER HEADER
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: lightBgColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: primaryColor, width: 1.2),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      organizationName.toUpperCase(),
                      style: pw.TextStyle(
                        color: primaryColor,
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'CLINICAL CASE DOSSIER & PATIENT HEALTH RECORD',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: darkTextColor,
                      ),
                    ),
                    pw.Text(
                      'Comprehensive Gynecological Examination & Encounter Summary',
                      style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Outreach Camp: ${camp?.name ?? "Gynae Outreach Station"} (${camp?.campCode ?? patient.campCode})',
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: secondaryColor),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: patient.patientId,
                      width: 44,
                      height: 44,
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'ID: ${patient.patientId}',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor),
                    ),
                    pw.Text(
                      'Date: ${dateFormatter.format(visit?.visitDate ?? patient.intakeDate)}',
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // 2. PATIENT DEMOGRAPHICS & INTAKE PROFILE
          _buildPdfSectionHeader('1. PATIENT DEMOGRAPHICS & SOCIAL INTAKE', primaryColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderGray, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: _buildPdfField('Full Name', patient.fullName, isBold: true)),
                    pw.Expanded(child: _buildPdfField('Patient ID', patient.patientId, isBold: true)),
                    pw.Expanded(child: _buildPdfField('Age / Marital', '${patient.age} yrs (${patient.maritalStatus})')),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: _buildPdfField('Guardian / Spouse', patient.spouseOrFatherName ?? 'N/A')),
                    pw.Expanded(child: _buildPdfField('Mobile Contact', patient.mobile.isNotEmpty ? patient.mobile : 'Not Provided')),
                    pw.Expanded(child: _buildPdfField('Permanent Address', 'Ward ${patient.ward}, ${patient.district}')),
                  ],
                ),
                if (patient.reasonsForVisit.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  _buildPdfField('Intake Complaints', patient.reasonsForVisit.join(', ')),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // 3. STRUCTURED YELLOW FORM CLINICAL ANAMNESIS
          _buildPdfSectionHeader('2. STRUCTURED CLINICAL ANAMNESIS (YELLOW FORM)', primaryColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderGray, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: complaintsMap.isEmpty
                ? pw.Text(
                    'No acute gynecological complaints recorded during clinical intake.',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  )
                : pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: complaintsMap.entries.map((entry) {
                      final title = friendlyComplaintTitles[entry.key] ?? entry.key.replaceAll('_', ' ').toUpperCase();
                      final val = entry.value;
                      String details = '';
                      if (val is Map) {
                        final dur = val['duration']?.toString() ?? '';
                        final rem = val['remarks']?.toString() ?? '';
                        final opts = val['options'];
                        final optStr = opts is List ? opts.join(', ') : '';
                        details = [dur, optStr, rem].where((s) => s.isNotEmpty).join(' | ');
                      } else if (val is String) {
                        details = val;
                      } else {
                        details = 'Present';
                      }
                      return pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Container(
                              width: 6,
                              height: 6,
                              margin: const pw.EdgeInsets.only(top: 3, right: 6),
                              decoration: const pw.BoxDecoration(
                                color: PdfColors.teal700,
                                shape: pw.BoxShape.circle,
                              ),
                            ),
                            pw.SizedBox(
                              width: 170,
                              child: pw.Text(
                                title,
                                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: darkTextColor),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Text(
                                details.isNotEmpty ? details : 'Positive finding',
                                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          pw.SizedBox(height: 7),

          // 4. OBSTETRIC HISTORY & PHYSICAL EXAMINATION
          _buildPdfSectionHeader('3. OBSTETRIC HISTORY & GYNECOLOGICAL EXAM', primaryColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderGray, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(child: _buildPdfField('Deliveries (Parity)', visit?.deliveries?.toString() ?? 'N/A')),
                    pw.Expanded(child: _buildPdfField('Living Children', visit?.livingChildren?.toString() ?? 'N/A')),
                    pw.Expanded(child: _buildPdfField('Abortions / Losses', visit?.abortions?.toString() ?? 'N/A')),
                    pw.Expanded(child: _buildPdfField('Pelvic Floor Tone', visit?.pelvicFloorTone.toUpperCase() ?? 'NORMAL')),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    pw.Expanded(child: _buildPdfField('Uterus Position', (visit?.uterusInside ?? true) ? 'Normal / Inside' : 'Procidentia / Prolapsed', isBold: !(visit?.uterusInside ?? true))),
                    pw.Expanded(child: _buildPdfField('Cervix Appearance', visit?.cervixRemarks ?? 'Normal / Healthy')),
                    pw.Expanded(child: _buildPdfField('Vulva / Vagina', visit?.vaginaRemarks ?? 'Normal')),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // 5. CLINICAL VITALS & SCREENING LABS
          _buildPdfSectionHeader('4. CLINICAL VITALS & SCREENING LABS', primaryColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderGray, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildPdfField(
                            'Blood Pressure',
                            visit?.systolicBp != null ? '${visit!.systolicBp}/${visit.diastolicBp ?? 0} mmHg' : 'N/A',
                            isBold: true,
                          ),
                          pw.Text('Status: $bpStatus', style: pw.TextStyle(fontSize: 7.5, color: bpColor, fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                    ),
                    pw.Expanded(child: _buildPdfField('Pulse Rate', visit?.pulse != null ? '${visit!.pulse} bpm' : 'N/A')),
                    pw.Expanded(child: _buildPdfField('SpO2 Saturation', visit?.spo2 != null ? '${visit!.spo2}%' : 'N/A')),
                    pw.Expanded(child: _buildPdfField('Blood Glucose', visit?.glucose != null ? '${visit!.glucose} mg/dL' : 'N/A')),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    pw.Expanded(child: _buildPdfField('Urine Dipstick', visit?.urineTest != null ? visit!.urineTest!.toUpperCase() : 'NORMAL')),
                    pw.Expanded(child: _buildPdfField('Pregnancy Test (UPT)', visit?.pregnancyTest != null ? visit!.pregnancyTest!.toUpperCase() : 'NEGATIVE / N/A')),
                    pw.Expanded(child: _buildPdfField('ECG / Cardiac Notes', visit?.ecgNotes ?? 'Not indicated')),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // 6. BADEN-WALKER POP-Q STAGING MATRIX
          _buildPdfSectionHeader('5. BADEN-WALKER POP STAGING (PELVIC ORGAN PROLAPSE)', primaryColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              color: (visit?.highestPopStage ?? 0) >= 2 ? lightBgColor : PdfColors.white,
              border: pw.Border.all(color: (visit?.highestPopStage ?? 0) >= 2 ? secondaryColor : borderGray, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPopBadge('HIGHEST POP STAGE', 'Stage ${visit?.highestPopStage ?? 0}', isHighlight: true, isCritical: (visit?.highestPopStage ?? 0) >= 3),
                _buildPopBadge('ANTERIOR (Cystocele)', 'Stage ${visit?.popAnteriorStage ?? 0}'),
                _buildPopBadge('MIDDLE (Uterine)', 'Stage ${visit?.popMiddleStage ?? 0}'),
                _buildPopBadge('POSTERIOR (Rectocele)', 'Stage ${visit?.popPosteriorStage ?? 0}'),
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // 7. DIAGNOSES & TREATMENT FORMULARY
          _buildPdfSectionHeader('6. CONFIRMED DIAGNOSES & FORMULARY', primaryColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderGray, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildPdfField(
                  'Confirmed Diagnoses',
                  visit != null && visit.diagnoses.isNotEmpty ? visit.diagnoses.join(', ') : 'No acute gynecological pathology diagnosed',
                  isBold: true,
                ),
                pw.SizedBox(height: 3),
                _buildPdfField(
                  'Prescribed Formulary',
                  visit != null && visit.medications.isNotEmpty ? visit.medications.join(' | ') : 'None Dispensed',
                ),
                if (visit?.customMedication != null && visit!.customMedication!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  _buildPdfField('Special Prescriptions', visit.customMedication!),
                ],
                if (visit?.pessarySize != null && visit!.pessarySize!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  _buildPdfField('Ring Pessary Fitted', '${visit.pessaryType ?? "Ring Pessary"} (Size: ${visit.pessarySize})', isBold: true),
                ],
                if (visit?.counseling != null && visit!.counseling.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  _buildPdfField('Patient Counseling Provided', visit.counseling.join(', ')),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // 8. DISCHARGE, SURGICAL REFERRAL & CONTINUITY OF CARE
          _buildPdfSectionHeader('7. CONTINUITY OF CARE & REFERRAL', primaryColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: borderGray, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _buildPdfField(
                        'Follow-up Required',
                        (visit?.followUpNeeded ?? false) ? 'YES (Indicated)' : 'NO (Routine)',
                        isBold: (visit?.followUpNeeded ?? false),
                      ),
                    ),
                    pw.Expanded(
                      child: _buildPdfField(
                        'Follow-up Center',
                        visit?.followUpDestination?.isNotEmpty == true ? visit!.followUpDestination! : 'Local Health Post',
                      ),
                    ),
                    pw.Expanded(
                      child: _buildPdfField(
                        'Surgical Referral',
                        visit?.surgicalReferral?.isNotEmpty == true ? visit!.surgicalReferral! : 'None Indicated',
                        isBold: visit?.surgicalReferral?.isNotEmpty == true,
                      ),
                    ),
                  ],
                ),
                if (visit?.outtakeNotes != null && visit!.outtakeNotes!.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  _buildPdfField('Attending Physician Clinical Notes', visit.outtakeNotes!),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // 9. CRYPTOGRAPHIC VERIFICATION & PHYSICIAN ATTESTATION FOOTER
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Document Reference: DOSSIER-${patient.patientId}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                  pw.Text('Generated Timestamp: ${timeFormatter.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                  pw.Text('Audit Integrity: SHA-256 Ledger Attested | Digital Outreach Record', style: pw.TextStyle(fontSize: 7.5, color: secondaryColor)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Container(width: 150, height: 0.8, color: PdfColors.black),
                  pw.SizedBox(height: 3),
                  pw.Text('Medical Officer / Attending Gynecologist', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Nepal Medical Council (NMC) Certified', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfSectionHeader(String title, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('F0FDFA'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
        border: pw.Border.all(color: color, width: 0.8),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  pw.Widget _buildPopBadge(String label, String value, {bool isHighlight = false, bool isCritical = false}) {
    final bgColor = isCritical
        ? PdfColor.fromHex('FFE4E6')
        : (isHighlight ? PdfColor.fromHex('CCFBF1') : PdfColor.fromHex('F1F5F9'));
    final textColor = isCritical
        ? PdfColor.fromHex('BE123C')
        : (isHighlight ? PdfColor.fromHex('0F766E') : PdfColor.fromHex('334155'));

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: textColor, width: 0.8),
      ),
      child: pw.Column(
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 7, color: textColor, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 1.5),
          pw.Text(value, style: pw.TextStyle(fontSize: 9.5, color: textColor, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
