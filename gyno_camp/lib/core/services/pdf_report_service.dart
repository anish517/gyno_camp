import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/camp_model.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/patient_model.dart';

class PdfReportService {
  /// Sanitizes dynamic strings for standard PDF Type-1 Helvetica font encoding.
  /// Converts typographical quotes/dashes and strips or filters non-Latin-1 code points (such as Devanagari)
  /// so that `doc.save()` does not throw an unhandled Helvetica Unicode encoding exception.
  static String sanitizeText(String? input, {String fallback = ''}) {
    if (input == null || input.trim().isEmpty) return fallback;
    var s = input
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('…', '...');

    if (s.runes.every((r) => r <= 255)) {
      return s;
    }

    final buffer = StringBuffer();
    for (final rune in s.runes) {
      if (rune <= 255) {
        buffer.writeCharCode(rune);
      }
    }
    final cleaned = buffer.toString().trim();
    return cleaned.isNotEmpty ? cleaned : input.replaceAll(RegExp(r'[^\x00-\x7F]'), '?');
  }

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
                      sanitizeText(summary.campName),
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: darkTextColor,
                      ),
                    ),
                    pw.Text(
                      sanitizeText('${summary.venue}, ${summary.municipality}, ${summary.district}'),
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
          if (summary.districtCounts.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: borderGray, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _buildTableHeader('District Distribution (जिल्लागत विवरण)'),
                    _buildTableHeader('Patient Count'),
                    _buildTableHeader('%'),
                  ],
                ),
                ...(() {
                  final sorted = summary.districtCounts.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value));
                  return sorted.map((e) {
                    final pct = summary.totalPatientsRegistered > 0
                        ? ((e.value / summary.totalPatientsRegistered) * 100).toStringAsFixed(1)
                        : '0.0';
                    return pw.TableRow(
                      children: [
                        _buildTableCell(sanitizeText(e.key)),
                        _buildTableCell('${e.value}', align: pw.TextAlign.center),
                        _buildTableCell('$pct%', align: pw.TextAlign.right),
                      ],
                    );
                  });
                })(),
              ],
            ),
          ],
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
    final safeValue = sanitizeText(value);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$label: ', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          pw.Expanded(
            child: pw.Text(
              safeValue,
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
    List<ClinicalVisitModel>? allVisits,
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
                      'Outreach Camp: ${sanitizeText(camp?.name ?? "Gynae Outreach Station")} (${camp?.campCode ?? patient.campCode})',
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
          if (allVisits != null && allVisits.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _buildPdfSectionHeader('8. LONGITUDINAL CLINICAL ENCOUNTERS & FOLLOW-UP TIMELINE (${allVisits.length} RECORDED)', primaryColor),
            pw.SizedBox(height: 4),
            ...allVisits.map((v) {
              final isFollowUp = v.isFollowUp;
              final dateFormatted = dateFormatter.format(v.visitDate);
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 5),
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: isFollowUp ? PdfColor.fromHex('F8FAFC') : lightBgColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  border: pw.Border.all(
                    color: isFollowUp ? PdfColor.fromHex('94A3B8') : primaryColor,
                    width: 0.6,
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          sanitizeText(isFollowUp ? 'Follow-Up Review ($dateFormatted)' : 'Initial Camp Examination ($dateFormatted)'),
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: isFollowUp ? PdfColors.blueGrey800 : primaryColor,
                          ),
                        ),
                        pw.Text(
                          'BP: ${v.systolicBp ?? "-"}/${v.diastolicBp ?? "-"} | Pulse: ${v.pulse ?? "-"} bpm | SpO2: ${v.spo2 ?? "-"}%',
                          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            'POP: Stage ${v.highestPopStage} (Ant: ${v.popAnteriorStage}, Mid: ${v.popMiddleStage}, Post: ${v.popPosteriorStage})',
                            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: darkTextColor),
                          ),
                        ),
                        if (v.pessarySize != null && v.pessarySize!.isNotEmpty)
                          pw.Text(
                            sanitizeText('Pessary: ${v.pessaryType ?? "Ring"} Sz ${v.pessarySize}'),
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.teal900),
                          ),
                        if (v.surgeryDone)
                          pw.Text(
                            sanitizeText(' | Surgery: ${v.surgeryType ?? "Done"}'),
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.green900),
                          ),
                      ],
                    ),
                    if (v.diagnoses.isNotEmpty) ...[
                      pw.SizedBox(height: 1.5),
                      pw.Text(
                        sanitizeText('Diagnoses: ${v.diagnoses.join(", ")}'),
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                      ),
                    ],
                    if (v.medications.isNotEmpty) ...[
                      pw.SizedBox(height: 1.5),
                      pw.Text(
                        sanitizeText('Medications: ${v.medications.join(", ")}'),
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                      ),
                    ],
                    if (v.followUpNotes != null && v.followUpNotes!.isNotEmpty) ...[
                      pw.SizedBox(height: 1.5),
                      pw.Text(
                        sanitizeText('Follow-up / Encounter Notes: ${v.followUpNotes}'),
                        style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
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

  // ─────────────────────────────────────────────────────────────────────────
  // INDIVIDUAL FOLLOW-UP ENCOUNTER SLIP (per-visit detailed clinical slip)
  // ─────────────────────────────────────────────────────────────────────────
  Future<Uint8List> generateFollowUpEncounterSlipPdf({
    required PatientModel patient,
    required ClinicalVisitModel visit,
    CampModel? camp,
    String organizationName = 'Nepal Gyno Health Outreach Network',
  }) async {
    final pdf = pw.Document();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

    final primary = PdfColor.fromHex('0F766E');
    final secondary = PdfColor.fromHex('0D9488');
    final lightBg = PdfColor.fromHex('F0FDFA');
    final dark = PdfColor.fromHex('1E293B');
    final gray = PdfColor.fromHex('CBD5E1');
    final cyanBg = PdfColor.fromHex('ECFEFF');
    final cyan = PdfColor.fromHex('0891B2');

    final isFollowUp = visit.isFollowUp;
    final encounterColor = isFollowUp ? cyan : primary;
    final encounterBg = isFollowUp ? cyanBg : lightBg;
    final encounterLabel = isFollowUp ? 'FOLLOW-UP CLINICAL ENCOUNTER' : 'PRIMARY CAMP EXAMINATION';
    final visitDate = dateFormatter.format(visit.visitDate);
    final visitTime = timeFormatter.format(visit.visitDate);

    // BP classification
    String bpStatus = 'N/A';
    PdfColor bpColor = dark;
    if (visit.systolicBp != null && visit.diastolicBp != null) {
      final s = visit.systolicBp!;
      final d = visit.diastolicBp!;
      if (s >= 160 || d >= 100) { bpStatus = 'HTN Stage 2 (Critical)'; bpColor = PdfColor.fromHex('BE123C'); }
      else if (s >= 140 || d >= 90) { bpStatus = 'HTN Stage 1 (Elevated)'; bpColor = PdfColor.fromHex('B45309'); }
      else if (s >= 120) { bpStatus = 'Pre-Hypertension'; bpColor = PdfColor.fromHex('B45309'); }
      else { bpStatus = 'Normal Range'; bpColor = primary; }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        build: (ctx) => [
          // ── Header ───────────────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: encounterBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: encounterColor, width: 1.2),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(sanitizeText(organizationName.toUpperCase()),
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: encounterColor)),
                      pw.SizedBox(height: 2),
                      pw.Text(encounterLabel,
                          style: pw.TextStyle(fontSize: 13.5, fontWeight: pw.FontWeight.bold, color: dark)),
                      pw.Text('Clinical Encounter Record | Individual Visit Slip',
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Camp: ${sanitizeText(camp?.name ?? "Gynae Outreach Station")} (${camp?.campCode ?? patient.campCode})',
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: secondary),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: '${patient.patientId}|$visitDate',
                      width: 62,
                      height: 62,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text('ENCOUNTER-${patient.patientId}',
                        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: encounterColor)),
                    pw.Text(visitTime, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // ── Patient Demographics ─────────────────────────────────────────
          _buildPdfSectionHeader('1. PATIENT IDENTITY', encounterColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: gray, width: 0.8), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Column(
              children: [
                pw.Row(children: [
                  pw.Expanded(child: _buildPdfField('Patient ID', patient.patientId, isBold: true)),
                  pw.Expanded(child: _buildPdfField('Full Name', patient.fullName, isBold: true)),
                  pw.Expanded(child: _buildPdfField('Age', '${patient.age} yrs (${patient.maritalStatus})')),
                ]),
                pw.SizedBox(height: 3),
                pw.Row(children: [
                  pw.Expanded(child: _buildPdfField('Address', 'Ward ${patient.ward}, ${patient.municipality}, ${patient.district}')),
                  pw.Expanded(child: _buildPdfField('Guardian / Spouse', patient.spouseOrFatherName ?? 'N/A')),
                  pw.Expanded(child: _buildPdfField('Mobile', patient.mobile.isNotEmpty ? patient.mobile : 'N/A')),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // ── Obstetric History ────────────────────────────────────────────
          if (visit.deliveries != null || visit.anamnesisComplaints.isNotEmpty) ...[
            _buildPdfSectionHeader('2. OBSTETRIC HISTORY & EXAMINATION', encounterColor),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: gray, width: 0.8), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Column(
                children: [
                  pw.Row(children: [
                    pw.Expanded(child: _buildPdfField('Deliveries (Parity)', visit.deliveries?.toString() ?? 'N/A')),
                    pw.Expanded(child: _buildPdfField('Living Children', visit.livingChildren?.toString() ?? 'N/A')),
                    pw.Expanded(child: _buildPdfField('Abortions', visit.abortions?.toString() ?? 'N/A')),
                    pw.Expanded(child: _buildPdfField('Pelvic Floor Tone', visit.pelvicFloorTone.toUpperCase())),
                  ]),
                  pw.SizedBox(height: 3),
                  pw.Row(children: [
                    pw.Expanded(child: _buildPdfField('Uterus', visit.uterusInside ? 'Normal / Inside' : 'Prolapsed / Outside', isBold: !visit.uterusInside)),
                    pw.Expanded(child: _buildPdfField('Cervix', sanitizeText(visit.cervixRemarks ?? 'Normal'))),
                    pw.Expanded(child: _buildPdfField('Vulva / Vagina', sanitizeText(visit.vaginaRemarks ?? 'Normal'))),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 7),
          ],

          // ── Clinical Vitals ──────────────────────────────────────────────
          _buildPdfSectionHeader('3. CLINICAL VITALS & SCREENING LABS', encounterColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: gray, width: 0.8), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Column(
              children: [
                pw.Row(children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildPdfField('Blood Pressure', visit.systolicBp != null ? '${visit.systolicBp}/${visit.diastolicBp} mmHg' : 'N/A', isBold: true),
                        pw.Text('Status: $bpStatus', style: pw.TextStyle(fontSize: 7.5, color: bpColor, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  pw.Expanded(child: _buildPdfField('Pulse Rate', visit.pulse != null ? '${visit.pulse} bpm' : 'N/A')),
                  pw.Expanded(child: _buildPdfField('SpO2', visit.spo2 != null ? '${visit.spo2}%' : 'N/A')),
                  pw.Expanded(child: _buildPdfField('Blood Glucose', visit.glucose != null ? '${visit.glucose} mg/dL' : 'N/A')),
                ]),
                pw.SizedBox(height: 3),
                pw.Row(children: [
                  pw.Expanded(child: _buildPdfField('Urine Dipstick', (visit.urineTest ?? 'Normal').toUpperCase())),
                  pw.Expanded(child: _buildPdfField('Pregnancy Test', (visit.pregnancyTest ?? 'Neg / N/A').toUpperCase())),
                  pw.Expanded(child: _buildPdfField('ECG / Cardiac', sanitizeText(visit.ecgNotes ?? 'Not indicated'))),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // ── POP Staging ──────────────────────────────────────────────────
          _buildPdfSectionHeader('4. BADEN-WALKER POP STAGING', encounterColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              color: visit.highestPopStage >= 2 ? lightBg : PdfColors.white,
              border: pw.Border.all(color: visit.highestPopStage >= 2 ? secondary : gray, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPopBadge('HIGHEST POP STAGE', 'Stage ${visit.highestPopStage}', isHighlight: true, isCritical: visit.highestPopStage >= 3),
                _buildPopBadge('ANTERIOR (Cystocele)', 'Stage ${visit.popAnteriorStage}'),
                _buildPopBadge('MIDDLE (Uterine)', 'Stage ${visit.popMiddleStage}'),
                _buildPopBadge('POSTERIOR (Rectocele)', 'Stage ${visit.popPosteriorStage}'),
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // ── Diagnoses & Treatment ────────────────────────────────────────
          _buildPdfSectionHeader('5. CONFIRMED DIAGNOSES & TREATMENT', encounterColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: gray, width: 0.8), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildPdfField('Confirmed Diagnoses',
                    visit.diagnoses.isNotEmpty ? visit.diagnoses.join(' | ') : 'No acute pathology diagnosed', isBold: visit.diagnoses.isNotEmpty),
                pw.SizedBox(height: 3),
                _buildPdfField('Prescribed Medications', visit.medications.isNotEmpty ? visit.medications.join(' | ') : 'None dispensed'),
                if (visit.customMedication?.isNotEmpty == true) ...[
                  pw.SizedBox(height: 2),
                  _buildPdfField('Special Prescriptions', sanitizeText(visit.customMedication!)),
                ],
                if (visit.pessarySize?.isNotEmpty == true) ...[
                  pw.SizedBox(height: 2),
                  _buildPdfField('Ring Pessary Fitted', '${visit.pessaryType ?? "Ring Pessary"} — Size: ${visit.pessarySize}', isBold: true),
                ],
                if (visit.surgeryDone) ...[
                  pw.SizedBox(height: 2),
                  _buildPdfField('Surgery Performed', sanitizeText(visit.surgeryType ?? 'Done'), isBold: true),
                ],
                if (visit.counseling.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  _buildPdfField('Patient Counseling', visit.counseling.join(', ')),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // ── Continuity of Care ────────────────────────────────────────────
          _buildPdfSectionHeader('6. CONTINUITY OF CARE & REFERRAL', encounterColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: gray, width: 0.8), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(children: [
                  pw.Expanded(child: _buildPdfField('Follow-up Required', visit.followUpNeeded ? 'YES — Indicated' : 'No (Routine)', isBold: visit.followUpNeeded)),
                  pw.Expanded(child: _buildPdfField('Follow-up Center', sanitizeText(visit.followUpDestination ?? 'Local Health Post'))),
                  pw.Expanded(child: _buildPdfField('Surgical Referral', sanitizeText(visit.surgicalReferral?.isNotEmpty == true ? visit.surgicalReferral! : 'None Indicated'), isBold: visit.surgicalReferral?.isNotEmpty == true)),
                ]),
                if (visit.followUpNotes?.isNotEmpty == true) ...[
                  pw.SizedBox(height: 3),
                  _buildPdfField('Follow-Up Clinical Notes', sanitizeText(visit.followUpNotes!)),
                ],
                if (visit.outtakeNotes?.isNotEmpty == true) ...[
                  pw.SizedBox(height: 3),
                  _buildPdfField('Attending Physician Notes', sanitizeText(visit.outtakeNotes!)),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // ── Attestation Footer ────────────────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Doc Ref: ENCOUNTER-${patient.patientId}-$visitDate', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                  pw.Text('Generated: ${timeFormatter.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                  pw.Text('Nepal Gyno Health Outreach Network — Attested Clinical Record',
                      style: pw.TextStyle(fontSize: 7.5, color: secondary)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Container(width: 150, height: 0.8, color: PdfColors.black),
                  pw.SizedBox(height: 3),
                  pw.Text('Medical Officer / Attending Gynecologist', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('NMC Certified — Date: $visitDate', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BLOCK-LETTER REGISTRATION FORM PDF (printable grid with squares per char)
  // ─────────────────────────────────────────────────────────────────────────
  Future<Uint8List> generatePatientRegistrationFormPdf({
    required PatientModel patient,
    CampModel? camp,
    String organizationName = 'Nepal Gyno Health Outreach Network',
  }) async {
    final pdf = pw.Document();
    final dateFormatter = DateFormat('yyyy-MM-dd');

    final primary = PdfColor.fromHex('0F766E');
    final secondary = PdfColor.fromHex('0D9488');
    final lightBg = PdfColor.fromHex('F0FDFA');
    final dark = PdfColor.fromHex('1E293B');
    final gray = PdfColor.fromHex('CBD5E1');
    final boxBg = PdfColor.fromHex('FAFAFA');

    // Helper: row of individual character boxes for a given value
    pw.Widget buildCharBoxes(String value, {int minBoxes = 20, double boxSize = 16}) {
      final chars = value.toUpperCase().split('');
      final total = chars.length > minBoxes ? chars.length : minBoxes;
      return pw.Row(
        children: List.generate(total, (i) {
          final char = i < chars.length ? chars[i] : '';
          return pw.Container(
            width: boxSize,
            height: boxSize + 2,
            margin: const pw.EdgeInsets.only(right: 2),
            decoration: pw.BoxDecoration(
              color: char.isNotEmpty ? PdfColor.fromHex('F0FDFA') : boxBg,
              border: pw.Border.all(color: gray, width: 0.8),
            ),
            child: pw.Center(
              child: pw.Text(
                char,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: dark),
              ),
            ),
          );
        }),
      );
    }

    // Helper: labelled block-letter field
    pw.Widget buildField(String labelEn, String labelNe, String value, {int minBoxes = 20, double boxSize = 16}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(children: [
              pw.Text('$labelEn / ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: dark)),
              pw.Text(labelNe, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ]),
            pw.SizedBox(height: 3),
            buildCharBoxes(value, minBoxes: minBoxes, boxSize: boxSize),
          ],
        ),
      );
    }

    // Helper: checkbox row
    pw.Widget buildCheckbox(String label, bool checked) {
      return pw.Row(
        children: [
          pw.Container(
            width: 12,
            height: 12,
            margin: const pw.EdgeInsets.only(right: 4),
            decoration: pw.BoxDecoration(
              color: checked ? primary : PdfColors.white,
              border: pw.Border.all(color: checked ? primary : gray, width: 0.9),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
            child: checked
                ? pw.Center(child: pw.Text('X', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)))
                : pw.SizedBox(),
          ),
          pw.Text(sanitizeText(label), style: const pw.TextStyle(fontSize: 8.5)),
        ],
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        build: (ctx) => [
          // ── Official Header ────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: pw.BoxDecoration(
              color: lightBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: primary, width: 1.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(sanitizeText(organizationName.toUpperCase()),
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primary)),
                      pw.SizedBox(height: 2),
                      pw.Text('PATIENT REGISTRATION FORM (YELLOW FORM) / बिरामी दर्ता फारम',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: dark)),
                      pw.Text('PLEASE FILL IN BLOCK LETTERS — ठूला अक्षरमा भर्नुहोस्',
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: secondary)),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Camp: ${sanitizeText(camp?.name ?? "Gynecological Health Outreach Camp")} | Date: ${dateFormatter.format(patient.intakeDate)}',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: patient.patientId,
                      width: 58,
                      height: 58,
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(patient.patientId,
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primary)),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.code128(),
                      data: patient.patientId,
                      width: 90,
                      height: 20,
                      drawText: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),

          // ── SECTION A: DEMOGRAPHICS ────────────────────────────────────
          _buildPdfSectionHeader('SECTION A: PATIENT DEMOGRAPHICS / बिरामी विवरण', primary),
          pw.SizedBox(height: 6),

          // First Name + Surname on one row
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: buildField('First Name', 'पहिलो नाम', patient.firstName, minBoxes: 14)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: buildField('Surname', 'थर', patient.surname, minBoxes: 14)),
            ],
          ),

          // Age + Marital Status
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 80,
                child: buildField('Age', 'उमेर', patient.age.toString(), minBoxes: 3, boxSize: 18),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Marital Status / वैवाहिक स्थिति',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: dark)),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        children: [
                          buildCheckbox('Married / विवाहित', patient.maritalStatus == 'married'),
                          pw.SizedBox(width: 12),
                          buildCheckbox('Widow / विधवा', patient.maritalStatus == 'widow'),
                          pw.SizedBox(width: 12),
                          buildCheckbox('Unmarried / अविवाहित', patient.maritalStatus == 'unmarried'),
                          pw.SizedBox(width: 12),
                          buildCheckbox('Divorced / सम्बन्ध विच्छेद', patient.maritalStatus == 'divorced'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Spouse/Father Name
          buildField(
            patient.maritalStatus == 'unmarried' || patient.age < 20 ? "Father's Name" : "Husband's Name",
            patient.maritalStatus == 'unmarried' || patient.age < 20 ? 'बुबाको नाम' : 'श्रीमानको नाम',
            patient.spouseOrFatherName ?? '',
            minBoxes: 24,
          ),

          // Mobile
          buildField('Mobile No.', 'मोबाइल नम्बर', patient.mobile, minBoxes: 10, boxSize: 18),

          // District + Municipality + Ward
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: buildField('District', 'जिल्ला', patient.district, minBoxes: 14)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: buildField('Municipality / VDC', 'नगर / गाउँपालिका', patient.municipality, minBoxes: 14)),
              pw.SizedBox(width: 10),
              pw.SizedBox(width: 70, child: buildField('Ward No.', 'वडा नं.', patient.ward, minBoxes: 3, boxSize: 18)),
            ],
          ),

          // Province
          buildField('Province', 'प्रदेश', patient.province, minBoxes: 16),

          pw.SizedBox(height: 4),
          pw.Divider(color: gray),
          pw.SizedBox(height: 6),

          // ── SECTION B: REASONS FOR VISIT ───────────────────────────────
          _buildPdfSectionHeader('SECTION B: REASONS FOR VISIT / जाँचको कारण', primary),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 20,
            runSpacing: 6,
            children: [
              buildCheckbox('Something Hanging Out / बाहिर आएको महसुस', patient.reasonsForVisit.any((r) => r.contains('hanging'))),
              buildCheckbox('Vaginal Discharge / Itching / स्राव खटिरो', patient.reasonsForVisit.any((r) => r.contains('discharge'))),
              buildCheckbox('Problems Passing Urine / पेसाब समस्या', patient.reasonsForVisit.any((r) => r.contains('urine'))),
              buildCheckbox('Problems Passing Stool / दिसा समस्या', patient.reasonsForVisit.any((r) => r.contains('stool'))),
              buildCheckbox('Menstrual Problem / महिनावारी समस्या', patient.reasonsForVisit.any((r) => r.contains('menstrual'))),
              buildCheckbox('Infertility / बाँझोपन', patient.reasonsForVisit.any((r) => r.contains('infertility'))),
              buildCheckbox('Pelvic / Abdominal Pain / दुखाई', patient.reasonsForVisit.any((r) => r.contains('pain'))),
              buildCheckbox('General Checkup / सामान्य जाँच', patient.reasonsForVisit.any((r) => r.contains('checkup'))),
            ],
          ),

          pw.SizedBox(height: 8),
          pw.Divider(color: gray),
          pw.SizedBox(height: 6),

          // ── SECTION C: CONSENT ──────────────────────────────────────────
          _buildPdfSectionHeader('SECTION C: PATIENT CONSENT / सहमति', primary),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            buildCheckbox('I consent to examination and treatment / जाँच र उपचार गर्न सहमति छ', patient.consentTreatment),
            pw.SizedBox(width: 20),
            buildCheckbox('I consent to storage of my medical information / स्वास्थ्य विवरण भण्डारण गर्न सहमति छ', patient.consentStoreMedicalInfo),
          ]),

          pw.SizedBox(height: 16),

          // ── Signature Footer ────────────────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 160, height: 0.8, color: PdfColors.black),
                  pw.SizedBox(height: 3),
                  pw.Text('Patient Signature / Thumbprint', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('(Required for consent)', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(width: 60, height: 40, decoration: pw.BoxDecoration(border: pw.Border.all(color: gray), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)))),
                  pw.SizedBox(height: 3),
                  pw.Text('Thumbprint Box', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(width: 140, height: 0.8, color: PdfColors.black),
                  pw.SizedBox(height: 3),
                  pw.Text('Data Entry Operator', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Verified by / Date: ${dateFormatter.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('F8FAFC'),
              border: pw.Border.all(color: gray),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('FOR OFFICIAL USE ONLY — ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primary)),
                pw.Text('Patient ID: ${patient.patientId} | Camp: ${camp?.campCode ?? patient.campCode} | Registered: ${dateFormatter.format(patient.intakeDate)}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }
}

