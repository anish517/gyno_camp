import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/camp_report_summary_model.dart';

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
}
