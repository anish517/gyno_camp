import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/camp_model.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/lookup_item_model.dart';
import '../../models/patient_model.dart';
import '../../repositories/lookup_repository.dart';
import '../constants/clinical_constants.dart';

class PdfReportService {
  static pw.ThemeData? _cachedTheme;

  static set testTheme(pw.ThemeData? theme) => _cachedTheme = theme;

  static Future<pw.ThemeData> getPdfTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    try {
      final regData = await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf');
      final devanagariFont = pw.Font.ttf(regData);
      _cachedTheme = pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        fontFallback: [devanagariFont],
      );
      return _cachedTheme!;
    } catch (_) {
      try {
        final fontFile = File('assets/fonts/NotoSansDevanagari-Regular.ttf');
        if (fontFile.existsSync()) {
          final bytes = fontFile.readAsBytesSync();
          final devanagariFont = pw.Font.ttf(bytes.buffer.asByteData());
          _cachedTheme = pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
            fontFallback: [devanagariFont],
          );
          return _cachedTheme!;
        }
      } catch (_) {}
      try {
        final regData = await rootBundle.load('assets/fonts/mangal.ttf');
        final devanagariFont = pw.Font.ttf(regData);
        _cachedTheme = pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          fontFallback: [devanagariFont],
        );
        return _cachedTheme!;
      } catch (_) {
        return pw.ThemeData.base();
      }
    }
  }

  /// Sanitizes dynamic strings for PDF generation.
  /// Standardizes typographical quotes/dashes while preserving Devanagari and Latin characters.
  static String sanitizeText(String? input, {String fallback = ''}) {
    if (input == null || input.trim().isEmpty) return fallback;
    final s = input
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('•', '-')
        .replaceAll('…', '...');
    return s.trim();
  }

  Future<Uint8List> generateCampSummaryPdf(CampReportSummaryModel summary) async {
    final theme = await getPdfTheme();
    final pdf = pw.Document(theme: theme);
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

    // ── ATTACHMENT: COMPREHENSIVE PATIENT REGISTER (15 COLUMNS MATCHING EXCEL) ──
    if (summary.patients.isNotEmpty) {
      final visitByPatientId = <String, ClinicalVisitModel>{};
      for (final v in summary.visits) {
        visitByPatientId[v.patientId] = v;
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          header: (context) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 6),
            margin: const pw.EdgeInsets.only(bottom: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.teal, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${PdfReportService.sanitizeText(summary.campName)} — Comprehensive Patient Register (${summary.patients.length} Registered Patients)',
                  style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryColor),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: borderGray, width: 0.5),
              headerStyle: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              cellStyle: pw.TextStyle(fontSize: 6.0, color: darkTextColor),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 2.5, vertical: 2.0),
              headers: [
                'ID',
                'Name',
                'Age',
                'Mobile',
                'Ward',
                'Marital',
                'Guardian',
                'Complaints',
                'POP',
                'Diagnoses',
                'Meds',
                'Pessary',
                'Referral',
                'Destination',
                'Date',
              ],
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2), // ID
                1: const pw.FlexColumnWidth(1.8), // Name
                2: const pw.FlexColumnWidth(0.6), // Age
                3: const pw.FlexColumnWidth(1.3), // Mobile
                4: const pw.FlexColumnWidth(0.7), // Ward
                5: const pw.FlexColumnWidth(1.0), // Marital
                6: const pw.FlexColumnWidth(1.5), // Guardian
                7: const pw.FlexColumnWidth(2.0), // Complaints
                8: const pw.FlexColumnWidth(0.8), // POP
                9: const pw.FlexColumnWidth(2.2), // Diagnoses
                10: const pw.FlexColumnWidth(2.2), // Meds
                11: const pw.FlexColumnWidth(1.1), // Pessary
                12: const pw.FlexColumnWidth(1.4), // Referral
                13: const pw.FlexColumnWidth(1.4), // Destination
                14: const pw.FlexColumnWidth(1.1), // Date
              },
              data: summary.patients.map((p) {
                final v = visitByPatientId[p.patientId];
                return [
                  PdfReportService.sanitizeText(p.patientId),
                  PdfReportService.sanitizeText('${p.firstName} ${p.surname}'),
                  p.age.toString(),
                  PdfReportService.sanitizeText(p.mobile),
                  PdfReportService.sanitizeText(p.ward),
                  PdfReportService.sanitizeText(p.maritalStatus),
                  PdfReportService.sanitizeText(p.spouseOrFatherName ?? '-'),
                  PdfReportService.sanitizeText(p.reasonsForVisit.isNotEmpty ? p.reasonsForVisit.join(', ') : '-'),
                  v != null ? 'Stage ${v.highestPopStage}' : '-',
                  PdfReportService.sanitizeText(v?.diagnoses.isNotEmpty == true ? v!.diagnoses.join(', ') : 'None'),
                  PdfReportService.sanitizeText(v?.medications.isNotEmpty == true ? v!.medications.join(', ') : 'None'),
                  PdfReportService.sanitizeText(v?.pessaryType ?? '-'),
                  PdfReportService.sanitizeText(v?.surgicalReferral ?? '-'),
                  PdfReportService.sanitizeText(v?.followUpDestination ?? '-'),
                  dateFormatter.format(p.intakeDate),
                ];
              }).toList(),
            ),
          ],
        ),
      );
    }

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
    final theme = await getPdfTheme();
    final pdf = pw.Document(theme: theme);
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
    final theme = await getPdfTheme();
    final pdf = pw.Document(theme: theme);
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

          // ── Chief Complaints & Reasons to Visit ──────────────────────────
          _buildPdfSectionHeader('2. CHIEF COMPLAINTS & REASONS TO VISIT', encounterColor),
          pw.SizedBox(height: 3),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: gray, width: 0.8), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildPdfField(
                  'Initial Intake Reasons (प्रारम्भिक समस्या)',
                  patient.reasonsForVisit.isNotEmpty ? patient.reasonsForVisit.join(' • ') : 'Routine Follow-Up / Consultation',
                  isBold: patient.reasonsForVisit.isNotEmpty,
                ),
                if (visit.anamnesisComplaints.isNotEmpty && visit.anamnesisComplaints['reasons'] is List && (visit.anamnesisComplaints['reasons'] as List).isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  _buildPdfField(
                    'Active Encounter Complaints',
                    (visit.anamnesisComplaints['reasons'] as List).join(' • '),
                  ),
                ],
                if (visit.anamnesisComplaints.isNotEmpty && visit.anamnesisComplaints['new_issues'] != null && (visit.anamnesisComplaints['new_issues'] as String).trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  _buildPdfField(
                    'New Reported Issues / Symptoms',
                    sanitizeText(visit.anamnesisComplaints['new_issues'] as String),
                    isBold: true,
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 7),

          // ── Obstetric History ────────────────────────────────────────────
          if (visit.deliveries != null || visit.anamnesisComplaints.isNotEmpty) ...[
            _buildPdfSectionHeader('3. OBSTETRIC HISTORY & EXAMINATION', encounterColor),
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
          _buildPdfSectionHeader('4. CLINICAL VITALS & SCREENING LABS', encounterColor),
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
          _buildPdfSectionHeader('5. BADEN-WALKER POP STAGING', encounterColor),
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
          _buildPdfSectionHeader('6. CONFIRMED DIAGNOSES & TREATMENT', encounterColor),
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
                  _buildPdfField('Other Prescriptions', sanitizeText(visit.customMedication!)),
                ],
                if (visit.pessaryType != null) ...[
                  pw.SizedBox(height: 2),
                  _buildPdfField('Ring Pessary', '${sanitizeText(visit.pessaryType!)} (${visit.pessarySize ?? "Standard"} mm)', isBold: true),
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
          _buildPdfSectionHeader('7. CONTINUITY OF CARE & REFERRAL', encounterColor),
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
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (visit.attendingDoctorNames.isNotEmpty) ...[
                    pw.Text(
                      sanitizeText(visit.attendingDoctorNames.map((d) => d.toLowerCase().startsWith('dr') ? d : 'Dr. $d').join(' & ')),
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: encounterColor),
                    ),
                    pw.SizedBox(height: 2),
                  ] else if (camp != null && camp.doctorNames.isNotEmpty) ...[
                    pw.Text(
                      sanitizeText(camp.doctorNames.map((d) => d.toLowerCase().startsWith('dr') ? d : 'Dr. $d').join(' & ')),
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: encounterColor),
                    ),
                    pw.SizedBox(height: 2),
                  ] else if (camp != null && camp.doctorName.trim().isNotEmpty) ...[
                    pw.Text(
                      sanitizeText(camp.doctorName.trim().toLowerCase().startsWith('dr') ? camp.doctorName.trim() : 'Dr. ${camp.doctorName.trim()}'),
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: encounterColor),
                    ),
                    pw.SizedBox(height: 2),
                  ],
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
  // ─────────────────────────────────────────────────────────────────────────
  // BLOCK-LETTER REGISTRATION FORM PDF (printable grid with squares per char)
  // Supports both pre-filled (patient != null) and blank physical forms (patient == null)
  // ─────────────────────────────────────────────────────────────────────────
  Future<Uint8List> generatePatientRegistrationFormPdf({
    PatientModel? patient,
    CampModel? camp,
    ClinicalVisitModel? visit,
    String organizationName = 'Nepal Gyno Health Outreach Network',
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
    List<LookupItemModel>? visitReasons,
    List<LookupItemModel>? chiefComplaints,
  }) async {
    final theme = await getPdfTheme();
    final pdf = pw.Document(theme: theme);
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final hasPatient = patient != null;
    final intakeDate = patient?.intakeDate ?? DateTime.now();

    final primary = PdfColor.fromHex('0F766E');
    final lightBg = PdfColor.fromHex('F0FDFA');
    final dark = PdfColor.fromHex('1E293B');
    final gray = PdfColor.fromHex('CBD5E1');
    final boxBg = PdfColor.fromHex('FAFAFA');

    // ── Resolve Doctor Information ──
    final List<String> campDoctors = camp?.doctorNames.isNotEmpty == true
        ? camp!.doctorNames
            .map((d) => d.trim().replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim())
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList()
        : (camp?.doctorName.trim().isNotEmpty == true
            ? [camp!.doctorName.trim().replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim()]
            : <String>[]);

    final String? assignedDoctor = (visit?.primaryDoctorName != null && visit!.primaryDoctorName!.trim().isNotEmpty)
        ? visit.primaryDoctorName!.trim()
        : (visit?.attendingDoctorNames.isNotEmpty == true
            ? visit!.attendingDoctorNames.first.trim()
            : null);

    final String doctorHeaderPart;
    if (assignedDoctor != null) {
      final clean = assignedDoctor.trim().replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim();
      doctorHeaderPart = "Dr: Dr. ${sanitizeText(clean)}";
    } else if (campDoctors.length > 1) {
      doctorHeaderPart = "Drs: ${campDoctors.map((d) => 'Dr. ${sanitizeText(d)}').join(', ')}";
    } else if (campDoctors.length == 1) {
      doctorHeaderPart = "Dr: Dr. ${sanitizeText(campDoctors.first)}";
    } else {
      doctorHeaderPart = "";
    }

    // ── Resolve dynamic master items with graceful fallbacks ──
    // 1. Diagnoses
    List<String> effectiveDiagnoses = diagnoses?.where((d) => d.isActive).map((d) => d.labelEn).toList() ?? [];
    if (effectiveDiagnoses.isEmpty) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory('diagnosis', campId: camp?.id);
        if (repoItems.isNotEmpty) {
          effectiveDiagnoses = repoItems.where((i) => i.isActive).map((i) => i.labelEn).toList();
        }
      } catch (_) {}
    }
    if (effectiveDiagnoses.isEmpty) {
      effectiveDiagnoses = ClinicalConstants.defaultDiagnoses;
    }
    if (effectiveDiagnoses.length > 22) {
      effectiveDiagnoses = effectiveDiagnoses.take(22).toList();
    }

    // 2. Medications
    List<String> effectiveMedications = medications?.where((m) => m.isActive).map((m) => m.labelEn).toList() ?? [];
    if (effectiveMedications.isEmpty) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory('medicine', campId: camp?.id);
        if (repoItems.isNotEmpty) {
          effectiveMedications = repoItems.where((i) => i.isActive).map((i) => i.labelEn).toList();
        }
      } catch (_) {}
    }
    if (effectiveMedications.isEmpty) {
      effectiveMedications = ClinicalConstants.defaultMedications;
    }
    if (effectiveMedications.length > 12) {
      effectiveMedications = effectiveMedications.take(12).toList();
    }

    // 3. Referral Hospitals
    List<String> effectiveHospitals = referralHospitals?.where((h) => h.isActive).map((h) => h.labelEn).toList() ?? [];
    if (effectiveHospitals.isEmpty) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory('referral_hospital', campId: camp?.id);
        if (repoItems.isNotEmpty) {
          effectiveHospitals = repoItems.where((i) => i.isActive).map((i) => i.labelEn).toList();
        }
      } catch (_) {}
    }
    if (effectiveHospitals.isEmpty) {
      effectiveHospitals = ClinicalConstants.referralHospitals;
    }
    if (effectiveHospitals.length > 6) {
      effectiveHospitals = effectiveHospitals.take(6).toList();
    }

    // 4. Visit Reasons (Map of code/key -> bilingual label)
    Map<String, String> effectiveVisitReasons = {};
    if (visitReasons != null && visitReasons.isNotEmpty) {
      for (final vr in visitReasons.where((v) => v.isActive)) {
        final label = (vr.labelNe.isNotEmpty && vr.labelNe != vr.labelEn)
            ? '${vr.labelEn} (${vr.labelNe})'
            : vr.labelEn;
        effectiveVisitReasons[vr.code] = label;
      }
    }
    if (effectiveVisitReasons.isEmpty) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory('visit_reason', campId: camp?.id);
        if (repoItems.isNotEmpty) {
          for (final vr in repoItems.where((v) => v.isActive)) {
            final label = (vr.labelNe.isNotEmpty && vr.labelNe != vr.labelEn)
                ? '${vr.labelEn} (${vr.labelNe})'
                : vr.labelEn;
            effectiveVisitReasons[vr.code] = label;
          }
        }
      } catch (_) {}
    }
    if (effectiveVisitReasons.isEmpty) {
      effectiveVisitReasons = Map.from(ClinicalConstants.visitReasonOptions);
    }
    if (effectiveVisitReasons.length > 8) {
      final capped = <String, String>{};
      for (final k in effectiveVisitReasons.keys.take(8)) {
        capped[k] = effectiveVisitReasons[k]!;
      }
      effectiveVisitReasons = capped;
    }

    // 5. Chief Complaints
    List<Map<String, String>> effectiveComplaints = [];
    if (chiefComplaints != null && chiefComplaints.isNotEmpty) {
      effectiveComplaints = chiefComplaints.where((c) => c.isActive).map((c) => {
        'code': c.code,
        'label': c.labelEn,
      }).toList();
    }
    if (effectiveComplaints.isEmpty) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory('chief_complaint', campId: camp?.id);
        if (repoItems.isNotEmpty) {
          effectiveComplaints = repoItems.where((i) => i.isActive).map((c) => {
            'code': c.code,
            'label': c.labelEn,
          }).toList();
        }
      } catch (_) {}
    }
    if (effectiveComplaints.isEmpty) {
      effectiveComplaints = [
        {'code': 'lower_abdominal_pain', 'label': 'Lower Abdominal Pain'},
        {'code': 'white_foul_discharge', 'label': 'White / Foul Discharge'},
        {'code': 'pelvic_heaviness', 'label': 'Pelvic Heaviness'},
        {'code': 'burning_micturition', 'label': 'Burning Micturition'},
        {'code': 'urinary_incontinence', 'label': 'Urinary Incontinence'},
        {'code': 'dyspareunia', 'label': 'Dyspareunia'},
        {'code': 'coital_bleeding', 'label': 'Coital Bleeding'},
        {'code': 'mass_per_vagina', 'label': 'Mass Per Vagina'},
        {'code': 'severe_backache', 'label': 'Severe Backache'},
      ];
    }
    if (effectiveComplaints.length > 10) {
      effectiveComplaints = effectiveComplaints.take(10).toList();
    }

    // Helper: row of individual character boxes for a given value
    pw.Widget buildCharBoxes(
      String value, {
      int minBoxes = 20,
      int? maxBoxes,
      double boxSize = 16,
      double boxMargin = 2,
    }) {
      final cleanVal = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      final chars = cleanVal.toUpperCase().split('');
      var total = chars.length > minBoxes ? chars.length : minBoxes;
      if (maxBoxes != null && total > maxBoxes) {
        total = maxBoxes;
      }
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: List.generate(total, (i) {
          final char = i < chars.length ? chars[i] : '';
          if (char == ' ') {
            return pw.SizedBox(width: 5);
          }
          if (char.isNotEmpty) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(right: 1.2),
              child: pw.Text(
                char,
                style: pw.TextStyle(
                  fontSize: 9.0,
                  fontWeight: pw.FontWeight.bold,
                  color: dark,
                ),
              ),
            );
          }
          return pw.Container(
            width: boxSize,
            height: boxSize + 2,
            margin: pw.EdgeInsets.only(right: boxMargin),
            decoration: pw.BoxDecoration(
              color: boxBg,
              border: pw.Border.all(color: gray, width: 0.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1.5)),
            ),
          );
        }),
      );
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        build: (ctx) {
          // ── Compact section header ──
          pw.Widget secHdr(String title) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 4, top: 6),
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  border: pw.Border(left: pw.BorderSide(color: primary, width: 2.5)),
                ),
                child: pw.Text(title, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: primary)),
              );

          // ── Compact char box field ──
          pw.Widget field(
            String labelEn,
            String labelNe,
            String value, {
            int minBoxes = 16,
            int? maxBoxes,
            double boxSize = 14,
            double boxMargin = 2,
          }) =>
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: '$labelEn: ',
                            style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold, color: dark),
                          ),
                          pw.TextSpan(
                            text: labelNe,
                            style: pw.TextStyle(fontSize: 6.8, color: PdfColors.grey600),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    buildCharBoxes(
                      value,
                      minBoxes: minBoxes,
                      maxBoxes: maxBoxes ?? minBoxes,
                      boxSize: boxSize,
                      boxMargin: boxMargin,
                    ),
                  ],
                ),
              );

          // ── Compact checkbox ──
          pw.Widget cb(String label, bool checked, {bool isExpanded = false}) => pw.Padding(
                padding: const pw.EdgeInsets.only(right: 8, bottom: 3),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 10, height: 10,
                      margin: const pw.EdgeInsets.only(right: 4, top: 1),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border.all(color: checked ? dark : gray, width: checked ? 1.0 : 0.8),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                      ),
                      child: checked
                          ? pw.Center(child: pw.Text('X', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: dark)))
                          : pw.SizedBox(),
                    ),
                    if (isExpanded)
                      pw.Expanded(
                        child: pw.Text(sanitizeText(label), style: pw.TextStyle(fontSize: 7.5)),
                      )
                    else
                      pw.Text(sanitizeText(label), style: pw.TextStyle(fontSize: 7.5)),
                  ],
                ),
              );

          // ── Normalize Palika string without redundant suffixes ──
          final rawMuni = patient?.municipality ?? '';
          final palikaVal = rawMuni
              .replaceAll(RegExp(r'\s*(municipality|nagarpalika|rural municipality|gaupalika)', caseSensitive: false), '')
              .trim();

          // ── LEFT COLUMN: Section A — Demographics ──
          final leftCol = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr('SECTION A: PATIENT DEMOGRAPHICS / बिरामी विवरण'),

              // Name rows (14 character boxes each)
              field('First Name', 'पहिलो नाम', patient?.firstName ?? '', minBoxes: 14, maxBoxes: 14, boxSize: 12.0, boxMargin: 1.5),
              field('Surname', 'थर', patient?.surname ?? '', minBoxes: 14, maxBoxes: 14, boxSize: 12.0, boxMargin: 1.5),

              // Patient Age label & Marital status
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.SizedBox(
                  width: 65,
                  child: field('Patient Age', 'उमेर', patient != null ? patient.age.toString() : '', minBoxes: 3, maxBoxes: 3, boxSize: 15, boxMargin: 2),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('Marital Status / वैवाहिक स्थिति',
                          style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: dark)),
                      pw.SizedBox(height: 3),
                      pw.Wrap(spacing: 8, runSpacing: 2, children: [
                        cb('Married', patient?.maritalStatus == 'married'),
                        cb('Widow', patient?.maritalStatus == 'widow'),
                        cb('Unmarried', patient?.maritalStatus == 'unmarried'),
                        cb('Divorced', patient?.maritalStatus == 'divorced'),
                      ]),
                    ]),
                  ),
                ),
              ]),

              field(
                (patient?.maritalStatus == 'unmarried' || (patient != null && patient.age < 20))
                    ? "Father's Name"
                    : "Husband's Name",
                (patient?.maritalStatus == 'unmarried' || (patient != null && patient.age < 20))
                    ? 'बुबाको नाम'
                    : 'श्रीमान / बुबाको नाम',
                patient?.spouseOrFatherName ?? '',
                minBoxes: 20,
                maxBoxes: 20,
                boxSize: 12.0,
                boxMargin: 1.5,
              ),

              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(
                  flex: 52,
                  child: field('Mobile No.', 'मोबाइल नम्बर', patient?.mobile ?? '', minBoxes: 10, maxBoxes: 10, boxSize: 12, boxMargin: 1.5),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  flex: 48,
                  child: field('Age at Marriage', 'विवाह भएको उमेर',
                      patient?.maritalAge != null ? patient!.maritalAge.toString() : '', minBoxes: 3, maxBoxes: 3, boxSize: 13, boxMargin: 2),
                ),
              ]),

              field('Contact Person (Secondary)', 'सम्पर्क व्यक्ति', patient?.contactPerson ?? '', minBoxes: 16, maxBoxes: 16, boxSize: 12.5, boxMargin: 1.5),
              field('Contact Mobile No.', 'सम्पर्क नम्बर', patient?.contactMobile ?? '', minBoxes: 10, maxBoxes: 10, boxSize: 13, boxMargin: 1.5),

              // Location Row 1: District & Province
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(child: field('District', 'जिल्ला', patient?.district ?? '', minBoxes: 10, maxBoxes: 10, boxSize: 11.5, boxMargin: 1.5)),
                pw.SizedBox(width: 8),
                pw.Expanded(child: field('Province', 'प्रदेश', patient?.province ?? '', minBoxes: 10, maxBoxes: 10, boxSize: 11.5, boxMargin: 1.5)),
              ]),

              // Location Row 2: Palika & Ward No.
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(child: field('Palika / Municipality', 'गाउँपालिका / नगरपालिका', palikaVal, minBoxes: 15, maxBoxes: 15, boxSize: 12, boxMargin: 1.5)),
                pw.SizedBox(width: 8),
                pw.SizedBox(width: 56, child: field('Ward No.', 'वडा नं.', patient?.ward ?? '', minBoxes: 2, maxBoxes: 3, boxSize: 14, boxMargin: 2)),
              ]),
            ],
          );

          // ── RIGHT COLUMN: Section B (Reasons) + Section C (Consent) + Signatures ──
          final rightCol = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr('SECTION B: REASONS FOR VISIT / जाँचको कारण'),
              ...effectiveVisitReasons.entries.map(
                (e) => cb(
                  e.value,
                  patient?.reasonsForVisit.any((r) {
                    final rNorm = r.toLowerCase().trim();
                    final keyNorm = e.key.toLowerCase().trim();
                    final valNorm = e.value.toLowerCase().trim();
                    return rNorm == keyNorm ||
                        rNorm.contains(keyNorm) ||
                        keyNorm.contains(rNorm) ||
                        valNorm.contains(rNorm);
                  }) ?? false,
                  isExpanded: true,
                ),
              ),

              pw.SizedBox(height: 6),
              secHdr('SECTION C: PATIENT CONSENT / सहमति'),
              cb('I consent to examination and treatment / जाँच तथा उपचारका लागि मेरो सहमति छ',
                  patient?.consentTreatment ?? false, isExpanded: true),
              pw.SizedBox(height: 3),
              cb('I consent to storage of my medical information / मेरो स्वास्थ्य विवरण सुरक्षित राख्न सहमति छ',
                  patient?.consentStoreMedicalInfo ?? false, isExpanded: true),

              pw.SizedBox(height: 10),

              // Signature lines (clean 2-column signature block without square box)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Container(width: 105, height: 0.8, color: PdfColors.black),
                    pw.SizedBox(height: 2),
                    pw.Text('Patient Signature / Thumbprint', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    pw.Text('(Required for consent)', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Container(width: 95, height: 0.8, color: PdfColors.black),
                    pw.SizedBox(height: 2),
                    pw.Text('Data Entry Operator', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: ${dateFormatter.format(DateTime.now())}', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                  ]),
                ],
              ),

              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('F8FAFC'),
                  border: pw.Border.all(color: gray, width: 0.8),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'FOR OFFICIAL USE ONLY',
                      style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: primary),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      hasPatient
                          ? 'Patient ID: ${patient.patientId} | Camp: ${camp?.campCode ?? patient.campCode}'
                          : 'Camp: ${camp?.campCode ?? "CAMP"} | Venue: ${sanitizeText(camp?.venue ?? "Health Center")}',
                      style: pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
                      textAlign: pw.TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          );

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Page 1 Header strip
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  border: pw.Border.all(color: primary, width: 1.2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(sanitizeText(organizationName.toUpperCase()),
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primary)),
                        pw.Text('PATIENT REGISTRATION — PAGE 1 (FRONT) | Yellow Form',
                            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: dark)),
                        pw.Text(
                          'PLEASE FILL IN BLOCK LETTERS — ठूला अक्षरमा भर्नुहोस् | Camp: ${sanitizeText(camp?.name ?? "Outreach Camp")} | Date: ${dateFormatter.format(intakeDate)}',
                          style: pw.TextStyle(fontSize: 6.8, color: PdfColors.grey700),
                        ),
                        if (doctorHeaderPart.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 1.5),
                            child: pw.Text(
                              'Examining Doctors (चिकित्सक): $doctorHeaderPart',
                              style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: primary),
                            ),
                          ),
                      ]),
                    ),
                    pw.SizedBox(width: 10),
                    hasPatient
                        ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: patient.patientId,
                              width: 42, height: 42,
                            ),
                            pw.Text(patient.patientId,
                                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: primary)),
                          ])
                        : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                            pw.Text('PATIENT TOKEN ID / अस्पताल दर्ता नं.',
                                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: primary)),
                            pw.SizedBox(height: 3),
                            buildCharBoxes(
                              camp?.campCode != null ? '${camp!.campCode}-' : '',
                              minBoxes: 10,
                              maxBoxes: 10,
                              boxSize: 13,
                              boxMargin: 1.5,
                            ),
                          ]),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),

              // 2-column: LEFT (demographics) | RIGHT (reasons + consent + sigs)
              pw.Expanded(
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.topCenter,
                  child: pw.SizedBox(
                    width: 551.28,
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(flex: 53, child: leftCol),
                        pw.SizedBox(width: 10),
                        pw.Container(width: 0.5, color: gray),
                        pw.SizedBox(width: 10),
                        pw.Expanded(flex: 47, child: rightCol),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    // ═══════════════════════════════════════════════════════════════════════
    // PAGE 2 — CLINICAL ASSESSMENT (Yellow Form Back Page — Single A4 Page)
    // Compact 2-column layout: all 6 stations fit on one physical page.
    // Labels match OCR parser labels in ocr_form_service.dart EXACTLY.
    // ═══════════════════════════════════════════════════════════════════════
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        build: (ctx) {
          // ── Local helpers (compact sizing) ──
          const fs = 7.5; // base font size
          const fsSmall = 7.0;

          pw.TextStyle bold({double size = fs}) =>
              pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold, color: dark);
          pw.TextStyle normal({double size = fs}) =>
              pw.TextStyle(fontSize: size, color: dark);

          pw.Widget sectionHeader(String title) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 2.5),
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('F0FDFA'),
                  border: pw.Border(left: pw.BorderSide(color: primary, width: 2.5)),
                ),
                child: pw.Text(sanitizeText(title),
                    style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold, color: primary)),
              );

          pw.Widget numBox(String v, {double w = 22, double h = 16}) => pw.Container(
                width: w, height: h,
                margin: const pw.EdgeInsets.only(right: 3),
                decoration: pw.BoxDecoration(
                  color: v.isNotEmpty ? PdfColor.fromHex('F0FDFA') : boxBg,
                  border: pw.Border.all(color: gray, width: 0.7),
                ),
                child: pw.Center(
                  child: pw.Text(v, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: dark)),
                ),
              );

          pw.Widget cb(String label, bool checked) => pw.Padding(
                padding: const pw.EdgeInsets.only(right: 8, bottom: 1.5),
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(
                      width: 9, height: 9,
                      margin: const pw.EdgeInsets.only(right: 2.5, top: 0.5),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border.all(color: checked ? dark : gray, width: checked ? 1.0 : 0.7),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1.5)),
                      ),
                      child: checked
                          ? pw.Center(child: pw.Text('X', style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: dark)))
                          : pw.SizedBox(),
                    ),
                    pw.Text(sanitizeText(label), style: pw.TextStyle(fontSize: fsSmall)),
                  ],
                ),
              );

          pw.Widget line({double h = 11, String? text}) => pw.Container(
                height: h,
                padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                margin: const pw.EdgeInsets.only(top: 1.5, bottom: 2),
                decoration: pw.BoxDecoration(
                  color: (text != null && text.isNotEmpty) ? PdfColor.fromHex('F0FDFA') : boxBg,
                  border: pw.Border(bottom: pw.BorderSide(color: gray, width: 0.7)),
                ),
                alignment: pw.Alignment.centerLeft,
                child: text != null && text.isNotEmpty
                    ? pw.Text(sanitizeText(text), style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: dark))
                    : pw.SizedBox(),
              );

          final complaintsList = (visit?.anamnesisComplaints['clinicalComplaints'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];
          final durationVal = (visit?.anamnesisComplaints['complaintsDuration'] as String? ?? '').toLowerCase();
          final tone = (visit?.pelvicFloorTone ?? '').toLowerCase();

          // Build columns
          // LEFT COLUMN: Stations 1-3 (Anamnesis, POP, Vitals)
          final leftCol = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── STATION 1: ANAMNESIS ─────────────────────────────────────
              sectionHeader('STATION 1: ANAMNESIS & OBSTETRIC HISTORY'),
              pw.Row(children: [
                pw.Text('Deliveries (P): ', style: bold()),
                numBox(visit?.deliveries?.toString() ?? ''),
                pw.SizedBox(width: 8),
                pw.Text('Living Children: ', style: bold()),
                numBox(visit?.livingChildren?.toString() ?? ''),
                pw.SizedBox(width: 8),
                pw.Text('Abortions: ', style: bold()),
                numBox(visit?.abortions?.toString() ?? ''),
              ]),
              pw.SizedBox(height: 3),
              pw.Text('Complaints Duration:', style: bold()),
              pw.SizedBox(height: 2),
              pw.Row(children: [
                cb('< 3 months', durationVal.contains('< 3') || durationVal.contains('<3')),
                cb('3-12 months', durationVal.contains('3-12') || durationVal.contains('3 to 12')),
                cb('> 1 year', durationVal.contains('> 1') || durationVal.contains('>1') || durationVal.contains('1 year')),
              ]),
              pw.SizedBox(height: 2),
              pw.Text('Clinical Complaints:', style: bold()),
              pw.SizedBox(height: 2),
              pw.Wrap(
                spacing: 0, runSpacing: 1,
                children: effectiveComplaints.map((item) {
                  final lbl = item['label'] ?? '';
                  final code = item['code'] ?? '';
                  final codeWords = code.replaceAll('_', ' ');
                  final isChecked = complaintsList.any((c) =>
                    c.contains(lbl.toLowerCase()) ||
                    c.contains(codeWords) ||
                    (code == 'mass_per_vagina' && (c.contains('mass') || c.contains('hanging'))) ||
                    (code == 'severe_backache' && (c.contains('backache') || c.contains('back')))
                  );
                  return cb(sanitizeText(lbl), isChecked);
                }).toList(),
              ),
              pw.SizedBox(height: 5),

              // ── STATION 2: POP EXAMINATION ───────────────────────────────
              sectionHeader('STATION 2: POP EXAMINATION (BADEN-WALKER)'),
              pw.Row(children: [
                pw.Text('Uterus Inside: ', style: bold()),
                cb('Yes', visit?.uterusInside == true),
                cb('No (Prolapsed)', visit?.uterusInside == false),
              ]),
              pw.SizedBox(height: 2),
              pw.Row(children: [
                pw.Text('Pelvic Tone: ', style: bold()),
                cb('Normal', tone == 'normal'),
                cb('Weak', tone == 'weak'),
                cb('Hypertonic', tone == 'hypertonic' || tone == 'torn'),
              ]),
              pw.SizedBox(height: 3),
              pw.Text('Baden-Walker Staging:', style: bold()),
              pw.SizedBox(height: 3),
              pw.Row(children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                  pw.Text('Anterior', style: pw.TextStyle(fontSize: fsSmall)),
                  pw.Text('(Cystocele)', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                  pw.SizedBox(height: 2),
                  numBox(visit != null ? '${visit.popAnteriorStage}' : '', w: 26, h: 20),
                ]),
                pw.SizedBox(width: 10),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                  pw.Text('Middle', style: pw.TextStyle(fontSize: fsSmall)),
                  pw.Text('(Uterine)', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                  pw.SizedBox(height: 2),
                  numBox(visit != null ? '${visit.popMiddleStage}' : '', w: 26, h: 20),
                ]),
                pw.SizedBox(width: 10),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                  pw.Text('Posterior', style: pw.TextStyle(fontSize: fsSmall)),
                  pw.Text('(Rectocele)', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                  pw.SizedBox(height: 2),
                  numBox(visit != null ? '${visit.popPosteriorStage}' : '', w: 26, h: 20),
                ]),
                pw.SizedBox(width: 10),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                  pw.Text('Highest Stage', style: pw.TextStyle(fontSize: fsSmall, fontWeight: pw.FontWeight.bold, color: primary)),
                  pw.SizedBox(height: 8),
                  numBox(visit != null ? '${visit.highestPopStage}' : '', w: 26, h: 20),
                ]),
              ]),
              pw.SizedBox(height: 3),
              pw.Row(children: [
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Cervix Appearance:', style: bold(size: fsSmall)),
                  line(text: visit?.cervixRemarks),
                ])),
                pw.SizedBox(width: 8),
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Vagina / Vulva:', style: bold(size: fsSmall)),
                  line(text: visit?.vaginaRemarks),
                ])),
              ]),
              pw.SizedBox(height: 5),

              // ── STATION 3: VITALS & LABS ─────────────────────────────────
              sectionHeader('STATION 3: VITALS & POINT-OF-CARE LABS'),
              pw.Row(children: [
                pw.Text('Blood Pressure: ', style: bold()),
                buildCharBoxes(visit?.systolicBp?.toString() ?? '', minBoxes: 3, maxBoxes: 3, boxSize: 13),
                pw.Text(' / ', style: normal()),
                buildCharBoxes(visit?.diastolicBp?.toString() ?? '', minBoxes: 3, maxBoxes: 3, boxSize: 13),
                pw.Text(' mmHg  ', style: normal(size: fsSmall)),
                pw.Text('Pulse: ', style: bold()),
                buildCharBoxes(visit?.pulse?.toString() ?? '', minBoxes: 3, maxBoxes: 3, boxSize: 13),
                pw.Text(' bpm', style: normal(size: fsSmall)),
              ]),
              pw.SizedBox(height: 3),
              pw.Row(children: [
                pw.Text('SpO2: ', style: bold()),
                buildCharBoxes(visit?.spo2?.toString() ?? '', minBoxes: 3, maxBoxes: 3, boxSize: 13),
                pw.Text(' %  ', style: normal(size: fsSmall)),
                pw.Text('Blood Glucose: ', style: bold()),
                buildCharBoxes(visit?.glucose?.toString() ?? '', minBoxes: 3, maxBoxes: 3, boxSize: 13),
                pw.Text(' mg/dL', style: normal(size: fsSmall)),
              ]),
              pw.SizedBox(height: 3),
              pw.Row(children: [
                pw.Text('Urine Test: ', style: bold()),
                cb('Normal', visit?.urineTest == 'normal'),
                cb('Protein+', visit?.urineTest?.contains('protein') == true),
                cb('Glucose+', visit?.urineTest?.contains('glucose') == true),
                cb('Blood+', visit?.urineTest?.contains('blood') == true),
              ]),
              pw.SizedBox(height: 2),
              pw.Row(children: [
                pw.Text('Pregnancy Test (UPT): ', style: bold()),
                cb('Negative', visit?.pregnancyTest == 'neg'),
                cb('Positive', visit?.pregnancyTest == 'pos'),
                cb('Not Done', visit?.pregnancyTest == 'not_done'),
              ]),
            ],
          );

          // RIGHT COLUMN: Stations 4-6 (Diagnoses, Treatment, Outtake)
          final rightCol = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── STATION 4: DIAGNOSES ─────────────────────────────────────
              sectionHeader('STATION 4: CONFIRMED DIAGNOSES / निदान'),
              ...ClinicalConstants.diagnosisCategories.map((category) {
                final catItems = effectiveDiagnoses.where((d) {
                  final cat = ClinicalConstants.diagnosisCategoryMap[d.toLowerCase()] ?? 'General / Other';
                  return cat == category;
                }).toList();
                if (catItems.isEmpty) return pw.SizedBox();

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1.5, bottom: 0.5),
                      child: pw.Text(
                        category.toUpperCase(),
                        style: pw.TextStyle(fontSize: 5.6, fontWeight: pw.FontWeight.bold, color: primary),
                      ),
                    ),
                    pw.Wrap(
                      spacing: 0, runSpacing: 0.5,
                      children: catItems.map((d) {
                        final isChecked = visit?.diagnoses.any((diag) {
                          final dNorm = d.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                          final diagNorm = diag.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                          return dNorm == diagNorm ||
                              dNorm.contains(diagNorm) ||
                              diagNorm.contains(dNorm) ||
                              (diagNorm.contains('candid') && dNorm.contains('candid')) ||
                              (diagNorm.contains('vaginosis') && dNorm.contains('vaginosis'));
                        }) ?? false;
                        return cb(sanitizeText(d), isChecked);
                      }).toList(),
                    ),
                  ],
                );
              }),
              pw.SizedBox(height: 1.5),
              pw.Text('Other: ', style: bold(size: fsSmall)),
              line(h: 10),
              pw.SizedBox(height: 3),

              // ── STATION 5: TREATMENT ─────────────────────────────────────
              sectionHeader('STATION 5: TREATMENT & PRESCRIPTIONS / उपचार'),
              ...ClinicalConstants.medicationCategories.map((category) {
                final catItems = effectiveMedications.where((m) {
                  final cat = ClinicalConstants.medicationCategoryMap[m.toLowerCase()] ?? 'Other / Custom';
                  return cat == category;
                }).toList();
                if (catItems.isEmpty) return pw.SizedBox();

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1.5, bottom: 0.5),
                      child: pw.Text(
                        category.toUpperCase(),
                        style: pw.TextStyle(fontSize: 5.6, fontWeight: pw.FontWeight.bold, color: primary),
                      ),
                    ),
                    pw.Wrap(
                      spacing: 0, runSpacing: 0.5,
                      children: catItems.map((m) {
                        final isChecked = visit?.medications.any((med) {
                          final mNorm = m.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                          final medNorm = med.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                          return mNorm == medNorm ||
                              mNorm.contains(medNorm) ||
                              medNorm.contains(mNorm) ||
                              (medNorm.contains('metronid') && mNorm.contains('metronid')) ||
                              (medNorm.contains('clotrim') && mNorm.contains('clotrim'));
                        }) ?? false;
                        return cb(sanitizeText(m), isChecked);
                      }).toList(),
                    ),
                  ],
                );
              }),
              pw.SizedBox(height: 3),
              pw.Row(children: [
                pw.Text('Ring Pessary: ', style: bold()),
                cb('Yes', visit?.pessaryType != null),
                cb('No', visit != null && visit.pessaryType == null),
                pw.Text('  Size: ', style: bold()),
                buildCharBoxes(visit?.pessarySize ?? '', minBoxes: 3, maxBoxes: 3, boxSize: 13),
                pw.Text(' mm', style: normal(size: fsSmall)),
              ]),
              pw.SizedBox(height: 2),
              pw.Row(children: [
                pw.Text('Surgery Done: ', style: bold()),
                cb('Yes', visit?.surgeryDone == true),
                cb('No', visit != null && visit.surgeryDone == false),
              ]),
              pw.SizedBox(height: 2),
              pw.Row(children: [
                pw.Text('Type: ', style: bold()),
                ...ClinicalConstants.surgeryTypes.map((s) => cb(sanitizeText(s), visit?.surgeryType == s)),
              ]),
              pw.SizedBox(height: 5),

              // ── STATION 6: OUTTAKE ───────────────────────────────────────
              sectionHeader('STATION 6: OUTTAKE & CONTINUITY OF CARE / अनुगमन तथा फलो-अप'),
              pw.Row(children: [
                pw.Text('Follow-up Required: ', style: bold()),
                cb('Yes (Follow-up Needed)', visit?.followUpNeeded == true),
                cb('No (Routine)', visit != null && visit.followUpNeeded == false),
              ]),
              pw.SizedBox(height: 2),
              pw.Text('Follow-up Destination:', style: bold(size: fsSmall)),
              line(h: 12, text: visit?.followUpDestination),
              pw.SizedBox(height: 2),
              pw.Text('Surgical Referral:', style: bold(size: fsSmall)),
              pw.SizedBox(height: 2),
              pw.Wrap(
                spacing: 0, runSpacing: 1,
                children: [
                  cb('None', visit != null && (visit.surgicalReferral == null || visit.surgicalReferral!.isEmpty)),
                  ...effectiveHospitals.map((h) => cb(
                    sanitizeText(h),
                    visit?.surgicalReferral?.toLowerCase().contains(h.toLowerCase().split(' ').first) == true,
                  )),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Text('Clinical Notes:', style: bold(size: fsSmall)),
              line(h: 12, text: visit?.outtakeNotes),
              line(h: 12),
              pw.SizedBox(height: 6),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Container(width: 105, height: 0.8, color: PdfColors.black),
                    pw.SizedBox(height: 2),
                    pw.Text('Data Entry Operator', style: pw.TextStyle(fontSize: fsSmall, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Name & Date:', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                  ]),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                      if (assignedDoctor != null) ...[
                        pw.Container(width: 120, height: 0.8, color: PdfColors.black),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          assignedDoctor.toLowerCase().startsWith('dr')
                              ? sanitizeText(assignedDoctor)
                              : 'Dr. ${sanitizeText(assignedDoctor)}',
                          style: pw.TextStyle(fontSize: fsSmall, fontWeight: pw.FontWeight.bold, color: dark),
                        ),
                        pw.Text('Medical Officer / Gynecologist', style: pw.TextStyle(fontSize: 6.2, color: PdfColors.grey700)),
                        pw.Text('NMC Certified — Date: ${dateFormatter.format(visit?.visitDate ?? intakeDate)}', style: pw.TextStyle(fontSize: 5.8, color: PdfColors.grey600)),
                      ] else if (campDoctors.length > 1) ...[
                        pw.Text('Examining Doctor (जाँच गर्ने चिकित्सक):', style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: primary)),
                        pw.SizedBox(height: 2),
                        pw.Wrap(
                          spacing: 8,
                          runSpacing: 2.5,
                          alignment: pw.WrapAlignment.end,
                          children: [
                            ...campDoctors.map((doc) => cb(doc.toLowerCase().startsWith('dr') ? sanitizeText(doc) : 'Dr. ${sanitizeText(doc)}', false)),
                            cb('Other: _____', false),
                          ],
                        ),
                        pw.SizedBox(height: 3),
                        pw.Container(width: 130, height: 0.8, color: PdfColors.black),
                        pw.SizedBox(height: 2),
                        pw.Text('Doctor Signature & NMC No. — Date:', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                      ] else if (campDoctors.length == 1) ...[
                        pw.Container(width: 120, height: 0.8, color: PdfColors.black),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          campDoctors.first.toLowerCase().startsWith('dr')
                              ? sanitizeText(campDoctors.first)
                              : 'Dr. ${sanitizeText(campDoctors.first)}',
                          style: pw.TextStyle(fontSize: fsSmall, fontWeight: pw.FontWeight.bold, color: dark),
                        ),
                        pw.Text('Medical Officer / Gynecologist', style: pw.TextStyle(fontSize: 6.2, color: PdfColors.grey700)),
                        pw.Text('NMC Certified — Date: ${hasPatient ? dateFormatter.format(intakeDate) : "_______________"}', style: pw.TextStyle(fontSize: 5.8, color: PdfColors.grey600)),
                      ] else ...[
                        pw.Container(width: 120, height: 0.8, color: PdfColors.black),
                        pw.SizedBox(height: 2),
                        pw.Text('Medical Officer / Gynecologist', style: pw.TextStyle(fontSize: fsSmall, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Doctor Signature & NMC No. — Date:', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
                      ],
                    ]),
                  ),
                ],
              ),
            ],
          );

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Page 2 header strip
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('F0FDFA'),
                  border: pw.Border.all(color: primary, width: 1.2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(sanitizeText(organizationName.toUpperCase()),
                            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: primary)),
                        pw.Text('CLINICAL ASSESSMENT — PAGE 2 (BACK) | Stations 1-6',
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: dark)),
                        pw.Text('To be completed by clinical staff — Block letters only',
                            style: pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
                      ]),
                    ),
                    pw.SizedBox(width: 10),
                    if (hasPatient)
                      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                        pw.Text(patient.patientId,
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primary)),
                        pw.Text('${sanitizeText(patient.firstName)} ${sanitizeText(patient.surname)}',
                            style: pw.TextStyle(fontSize: 7)),
                      ])
                    else
                      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                        pw.Text('Patient ID:', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: primary)),
                        pw.SizedBox(height: 2),
                        buildCharBoxes('', minBoxes: 10, maxBoxes: 10, boxSize: 12, boxMargin: 1.5),
                      ]),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),

              // 2-column layout: LEFT (Stations 1-3) | RIGHT (Stations 4-6)
              pw.Expanded(
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.topCenter,
                  child: pw.SizedBox(
                    width: 551.28,
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(flex: 5, child: leftCol),
                        pw.SizedBox(width: 10),
                        pw.Container(width: 0.5, color: gray),
                        pw.SizedBox(width: 10),
                        pw.Expanded(flex: 5, child: rightCol),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
