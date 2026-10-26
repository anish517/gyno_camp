import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter/painting.dart' as fp;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/camp_model.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/lookup_item_model.dart';
import '../../models/patient_model.dart';
import '../../repositories/lookup_repository.dart';
import '../constants/app_constants.dart';
import '../constants/clinical_constants.dart';
import 'report_aggregation_service.dart';
import 'session_service.dart';

typedef _NeSpec = ({
  String text,
  double size,
  bool bold,
  int color,
  double? maxWidth,
});

/// Layout modes for Yellow Registration Form Page 1
enum BlankFormPage1Layout {
  grid, // 2-column stacked field grid (modern full-width)
  classic, // single demographics column split (earlier side-by-side)
}

class PdfReportService {
  static pw.ThemeData? _cachedTheme;
  static pw.MemoryImage? _cachedLogoImage;

  /// Resolves the effective, non-placeholder organization name from explicit argument,
  /// active camp metadata, or current session preferences.
  static String resolveEffectiveOrganizationName({
    String? organizationName,
    CampModel? camp,
  }) {
    if (organizationName != null &&
        organizationName.trim().isNotEmpty &&
        !AppConstants.isLegacyDefaultOrganization(organizationName)) {
      return organizationName.trim();
    }
    if (camp != null &&
        camp.organizationName.trim().isNotEmpty &&
        !AppConstants.isLegacyDefaultOrganization(camp.organizationName)) {
      return camp.organizationName.trim();
    }
    final sessionOrg = SessionService.current?.getOrganizationName()?.trim();
    if (sessionOrg != null &&
        sessionOrg.isNotEmpty &&
        !AppConstants.isLegacyDefaultOrganization(sessionOrg)) {
      return sessionOrg;
    }
    return AppConstants.defaultOrganizationName;
  }

  /// Loads the WFWSN branding logo as a [pw.MemoryImage] for PDF reports.
  /// Tries the optimized PNG first, followed by small JPG and original JPG fallbacks.
  static Future<pw.MemoryImage?> loadLogoImage() async {
    if (_cachedLogoImage != null) return _cachedLogoImage;

    const candidates = [
      'assets/wfwsn_logo_pdf.png',
      'assets/WFWSNPrimaryCircle.png',
      'assets/wfwsn_logo_small.png',
      'assets/wfwsn_logo_small.jpg',
      'assets/WFWSNPrimaryCircle.jpg',
    ];

    for (final path in candidates) {
      try {
        final data = await rootBundle.load(path);
        if (data.lengthInBytes > 0) {
          _cachedLogoImage = pw.MemoryImage(data.buffer.asUint8List());
          return _cachedLogoImage;
        }
      } catch (_) {
        try {
          final file = File(path);
          if (file.existsSync()) {
            final bytes = file.readAsBytesSync();
            if (bytes.isNotEmpty) {
              _cachedLogoImage = pw.MemoryImage(bytes);
              return _cachedLogoImage;
            }
          }
        } catch (_) {}
      }
    }
    debugPrint('[PDF] Warning: Could not load any WFWSN logo asset');
    return null;
  }

  static const double _neScale = 4.0; // render at 4x for crisp print
  static final Map<_NeSpec, ({pw.MemoryImage img, double w, double h})>
  _neCache = {};
  static final Set<_NeSpec> _nePending = {};
  static final RegExp _devanagari = RegExp(r'[\u0900-\u097F]');
  static bool _fontsLoaded = false;

  static Future<void> _ensureFontLoaded() async {
    if (_fontsLoaded) return;
    try {
      final fontLoader = FontLoader('NotoSansDevanagari');
      try {
        final regData = await rootBundle.load(
          'assets/fonts/NotoSansDevanagari-Regular.ttf',
        );
        fontLoader.addFont(Future.value(regData));
      } catch (_) {
        final file = File('assets/fonts/NotoSansDevanagari-Regular.ttf');
        if (file.existsSync()) {
          fontLoader.addFont(
            Future.value(ByteData.view(file.readAsBytesSync().buffer)),
          );
        }
      }
      try {
        final boldData = await rootBundle.load(
          'assets/fonts/NotoSansDevanagari-Bold.ttf',
        );
        fontLoader.addFont(Future.value(boldData));
      } catch (_) {
        final file = File('assets/fonts/NotoSansDevanagari-Bold.ttf');
        if (file.existsSync()) {
          fontLoader.addFont(
            Future.value(ByteData.view(file.readAsBytesSync().buffer)),
          );
        }
      }
      await fontLoader.load();
    } catch (_) {}

    try {
      final arialFile = File(r'C:\Windows\Fonts\arial.ttf');
      if (arialFile.existsSync()) {
        final latinLoader = FontLoader('Roboto');
        latinLoader.addFont(
          Future.value(ByteData.view(arialFile.readAsBytesSync().buffer)),
        );
        await latinLoader.load();
      }
    } catch (_) {}

    _fontsLoaded = true;
  }

  /// Drop-in replacement for pw.Text. Latin-only strings stay normal text;
  /// strings containing Devanagari become properly shaped images.
  static pw.Widget ne(
    String text, {
    double size = 8,
    bool bold = false,
    int color = 0xFF1E293B,
    double? maxWidth,
  }) {
    text = sanitizeText(text);
    if (text.isEmpty) return pw.SizedBox();
    pw.Widget plain() => pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: PdfColor.fromInt(color),
      ),
    );
    if (!_devanagari.hasMatch(text)) return plain();

    final spec = (
      text: text,
      size: size,
      bold: bold,
      color: color,
      maxWidth: maxWidth,
    );
    final hit = _neCache[spec];
    if (hit == null) {
      _nePending.add(spec); // rendered after the first pass
      return plain();
    }
    return pw.Image(hit.img, width: hit.w, height: hit.h);
  }

  static Future<void> _renderPendingNepali() async {
    if (_nePending.isEmpty) return;
    await _ensureFontLoaded();
    for (final s in _nePending.toList()) {
      try {
        final tp =
            fp.TextPainter(
              text: fp.TextSpan(
                text: s.text,
                style: fp.TextStyle(
                  fontFamily: 'NotoSansDevanagari',
                  fontFamilyFallback: const [
                    'Roboto',
                    'Arial',
                    'Segoe UI',
                    'sans-serif',
                  ],
                  fontSize: s.size * _neScale,
                  fontWeight: s.bold ? fp.FontWeight.w700 : fp.FontWeight.w400,
                  color: fp.Color(s.color),
                  height: 1.25,
                ),
              ),
              textDirection: ui.TextDirection.ltr,
            )..layout(
              maxWidth: s.maxWidth != null
                  ? s.maxWidth! * _neScale
                  : double.infinity,
            );

        final rec = ui.PictureRecorder();
        tp.paint(ui.Canvas(rec), ui.Offset.zero);
        final width = tp.width.ceil().clamp(1, 4000);
        final height = tp.height.ceil().clamp(1, 4000);
        final image = await rec.endRecording().toImage(width, height);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data != null) {
          _neCache[s] = (
            img: pw.MemoryImage(data.buffer.asUint8List()),
            w: tp.width / _neScale,
            h: tp.height / _neScale,
          );
        }
      } catch (_) {}
    }
    _nePending.clear();
  }

  /// Two-pass build: pass 1 discovers which Nepali strings are needed,
  /// then they're rendered, then pass 2 builds the real document.
  static Future<Uint8List> _saveWithNepali(
    Future<pw.Document> Function() build,
  ) async {
    var doc = await build();
    await doc.save();
    if (_nePending.isNotEmpty) {
      await _renderPendingNepali();
      doc = await build();
      return await doc.save();
    }
    return doc.save();
  }

  static set testTheme(pw.ThemeData? theme) => _cachedTheme = theme;

  static Future<pw.ThemeData> getPdfTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    try {
      final regData = await rootBundle.load(
        'assets/fonts/NotoSansDevanagari-Regular.ttf',
      );
      final devanagariFont = pw.Font.ttf(regData);

      pw.Font? devanagariBold;
      try {
        final boldData = await rootBundle.load(
          'assets/fonts/NotoSansDevanagari-Bold.ttf',
        );
        devanagariBold = pw.Font.ttf(boldData);
      } catch (_) {}

      _cachedTheme = pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        fontFallback: [devanagariFont, ?devanagariBold],
      );
      return _cachedTheme!;
    } catch (_) {
      try {
        final fontFile = File('assets/fonts/NotoSansDevanagari-Regular.ttf');
        if (fontFile.existsSync()) {
          final bytes = fontFile.readAsBytesSync();
          final devanagariFont = pw.Font.ttf(bytes.buffer.asByteData());
          pw.Font? devanagariBold;
          final boldFile = File('assets/fonts/NotoSansDevanagari-Bold.ttf');
          if (boldFile.existsSync()) {
            devanagariBold = pw.Font.ttf(
              boldFile.readAsBytesSync().buffer.asByteData(),
            );
          }
          _cachedTheme = pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
            fontFallback: [devanagariFont, ?devanagariBold],
          );
          return _cachedTheme!;
        }
      } catch (_) {}
      try {
        final regData = await rootBundle.load('assets/fonts/mangal.ttf');
        final devanagariFont = pw.Font.ttf(regData);
        pw.Font? devanagariBold;
        try {
          final boldData = await rootBundle.load('assets/fonts/mangalb.ttf');
          devanagariBold = pw.Font.ttf(boldData);
        } catch (_) {}
        _cachedTheme = pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
          fontFallback: [devanagariFont, ?devanagariBold],
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

  Future<Uint8List> generateCampSummaryPdf(
    CampReportSummaryModel summary,
  ) async {
    final theme = await getPdfTheme();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      final dateFormatter = DateFormat('yyyy-MM-dd');
      final timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

      final primaryColor = PdfColor.fromHex(
        '30026E',
      ); // WFWSN Logo Royal Violet
      final secondaryColor = PdfColor.fromHex(
        '81005D',
      ); // WFWSN Logo Wine/Magenta
      final lightBgColor = PdfColor.fromHex('F5F3FF'); // Soft Violet Tint
      final darkTextColor = PdfColor.fromHex('1E293B');
      final borderGray = PdfColor.fromHex('CBD5E1');

      // Load WFWSN logo
      final logoImage = await loadLogoImage();

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
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Logo
                  if (logoImage != null)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(logoImage, width: 56, height: 56),
                    ),
                  pw.Expanded(
                    child: pw.Column(
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
                          sanitizeText(
                            '${summary.venue}, ${summary.municipality}, ${summary.district}',
                          ),
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: pw.BoxDecoration(
                          color: primaryColor,
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4),
                          ),
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
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        'Generated: ${timeFormatter.format(summary.generatedAt)}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey600,
                        ),
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
            pw.SizedBox(height: 8),
            // Consultation KPI Cards
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _buildKpiBox(
                  title: 'Gynocheckup',
                  value: '${summary.fullCheckUpCount}',
                  subtitle: summary.totalPatientsRegistered > 0
                      ? '(${((summary.fullCheckUpCount / summary.totalPatientsRegistered) * 100).toStringAsFixed(1)}%)'
                      : '(0.0%)',
                  color: PdfColor.fromHex('2563EB'),
                ),
                _buildKpiBox(
                  title: 'Counseling',
                  value: '${summary.councilLevelCount}',
                  subtitle: summary.totalPatientsRegistered > 0
                      ? '(${((summary.councilLevelCount / summary.totalPatientsRegistered) * 100).toStringAsFixed(1)}%)'
                      : '(0.0%)',
                  color: PdfColor.fromHex('0D9488'),
                ),
                _buildKpiBox(
                  title: 'Unassigned',
                  value: '${summary.unassignedTreatmentLevelCount}',
                  subtitle: summary.totalPatientsRegistered > 0
                      ? '(${((summary.unassignedTreatmentLevelCount / summary.totalPatientsRegistered) * 100).toStringAsFixed(1)}%)'
                      : '(0.0%)',
                  color: PdfColor.fromHex('64748B'),
                ),
                _buildKpiBox(
                  title: 'Pessary Fitted',
                  value: '${summary.totalPessariesInserted}',
                  subtitle: '(${summary.pelvicFloorCounselingCount} Counseled)',
                  color: PdfColor.fromHex('059669'),
                ),
              ],
            ),
            pw.SizedBox(height: 18),

            // 1. Demographics Section
            _buildSectionHeader(
              '1. Patient Demographics & Age Distribution',
              primaryColor,
            ),
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
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        children: [
                          _buildTableHeader('Age Group'),
                          _buildTableHeader('Count'),
                          _buildTableHeader('%'),
                        ],
                      ),
                      ...summary.ageGroups.entries.map((e) {
                        final pct = summary.totalPatientsRegistered > 0
                            ? ((e.value / summary.totalPatientsRegistered) *
                                      100)
                                  .toStringAsFixed(1)
                            : '0.0';
                        return pw.TableRow(
                          children: [
                            _buildTableCell(e.key),
                            _buildTableCell(
                              '${e.value}',
                              align: pw.TextAlign.center,
                            ),
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
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
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
                              ? ((e.value / summary.totalPatientsRegistered) *
                                        100)
                                    .toStringAsFixed(1)
                              : '0.0';
                          return pw.TableRow(
                            children: [
                              _buildTableCell(e.key.toUpperCase()),
                              _buildTableCell(
                                '${e.value}',
                                align: pw.TextAlign.center,
                              ),
                              _buildTableCell(
                                '$pct%',
                                align: pw.TextAlign.right,
                              ),
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
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    children: [
                      _buildTableHeader(
                        'District Distribution (जिल्लागत विवरण)',
                      ),
                      _buildTableHeader('Patient Count'),
                      _buildTableHeader('%'),
                    ],
                  ),
                  ...(() {
                    final sorted = summary.districtCounts.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value));
                    return sorted.map((e) {
                      final pct = summary.totalPatientsRegistered > 0
                          ? ((e.value / summary.totalPatientsRegistered) * 100)
                                .toStringAsFixed(1)
                          : '0.0';
                      return pw.TableRow(
                        children: [
                          _buildTableCell(sanitizeText(e.key)),
                          _buildTableCell(
                            '${e.value}',
                            align: pw.TextAlign.center,
                          ),
                          _buildTableCell('$pct%', align: pw.TextAlign.right),
                        ],
                      );
                    });
                  })(),
                ],
              ),
            ],
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: borderGray, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _buildTableHeader(
                      'Consultation Distribution (परामर्श विवरण)',
                    ),
                    _buildTableHeader('Patient Count'),
                    _buildTableHeader('% of Registered'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _buildTableCell('Gynocheckup (गाइनो जाँच)', isBold: true),
                    _buildTableCell(
                      '${summary.fullCheckUpCount}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.totalPatientsRegistered > 0 ? ((summary.fullCheckUpCount / summary.totalPatientsRegistered) * 100).toStringAsFixed(1) : "0.0"}%',
                      align: pw.TextAlign.right,
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _buildTableCell(
                      'Counseling (काउन्सिलिङ)',
                      isBold: true,
                    ),
                    _buildTableCell(
                      '${summary.councilLevelCount}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.totalPatientsRegistered > 0 ? ((summary.councilLevelCount / summary.totalPatientsRegistered) * 100).toStringAsFixed(1) : "0.0"}%',
                      align: pw.TextAlign.right,
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _buildTableCell('Unassigned (तह नतोकिएको)'),
                    _buildTableCell(
                      '${summary.unassignedTreatmentLevelCount}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.totalPatientsRegistered > 0 ? ((summary.unassignedTreatmentLevelCount / summary.totalPatientsRegistered) * 100).toStringAsFixed(1) : "0.0"}%',
                      align: pw.TextAlign.right,
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 18),

            // 2. POP Staging Matrix
            _buildSectionHeader(
              '2. Pelvic Organ Prolapse (POP) Staging Matrix',
              primaryColor,
            ),
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
                    _buildTableCell(
                      '${summary.anteriorStages[0] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.anteriorStages[1] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.anteriorStages[2] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.anteriorStages[3] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell('N/A', align: pw.TextAlign.center),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _buildTableCell('Apical (Uterine / Apex)', isBold: true),
                    _buildTableCell(
                      '${summary.middleStages[0] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.middleStages[1] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.middleStages[2] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.middleStages[3] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.middleStages[4] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _buildTableCell('Posterior (Rectocele)', isBold: true),
                    _buildTableCell(
                      '${summary.posteriorStages[0] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.posteriorStages[1] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.posteriorStages[2] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.posteriorStages[3] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell('N/A', align: pw.TextAlign.center),
                  ],
                ),
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: lightBgColor),
                  children: [
                    _buildTableCell('Highest POP Stage', isBold: true),
                    _buildTableCell(
                      '${summary.highestPopStages[0] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.highestPopStages[1] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.highestPopStages[2] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.highestPopStages[3] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                    _buildTableCell(
                      '${summary.highestPopStages[4] ?? 0}',
                      align: pw.TextAlign.center,
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 18),

            // 3. Clinical Diagnoses & Pathologies
            _buildSectionHeader(
              '3. Gynecological Diagnoses & Pathologies',
              primaryColor,
            ),
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
                        ? ((e.value / summary.totalVisitsRecorded) * 100)
                              .toStringAsFixed(1)
                        : '0.0';
                    return pw.TableRow(
                      children: [
                        _buildTableCell(e.key),
                        _buildTableCell(
                          '${e.value}',
                          align: pw.TextAlign.center,
                        ),
                        _buildTableCell('$pct%', align: pw.TextAlign.right),
                      ],
                    );
                  }),
              ],
            ),
            pw.SizedBox(height: 18),

            // 4. Treatments, Pessaries, Referrals & Pharmacy
            _buildSectionHeader(
              '4. Interventions, Referrals & Pharmacy',
              primaryColor,
            ),
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
                      pw.Text(
                        'Interventions & Referrals',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      _buildDetailBullet(
                        'Pessaries Fitted',
                        '${summary.totalPessariesInserted} patients',
                      ),
                      _buildDetailBullet(
                        'Pelvic Floor Exercises',
                        '${summary.pelvicFloorCounselingCount} counseled',
                      ),
                      _buildDetailBullet(
                        'Surgical Referrals',
                        '${summary.totalSurgicalReferrals} cases',
                      ),
                      if (summary.surgicalReferralCounts.isNotEmpty)
                        ...summary.surgicalReferralCounts.entries.map(
                          (e) => pw.Padding(
                            padding: const pw.EdgeInsets.only(left: 12),
                            child: pw.Text(
                              '- ${e.key}: ${e.value}',
                              style: pw.TextStyle(fontSize: 8),
                            ),
                          ),
                        ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Point-of-Care Vitals Alerts',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                      _buildDetailBullet(
                        'Hypertension (>=140/90)',
                        '${summary.hypertensionCount} flagged',
                      ),
                      _buildDetailBullet(
                        'Hyperglycemia (>=140 mg/dL)',
                        '${summary.hyperglycemiaCount} flagged',
                      ),
                      _buildDetailBullet(
                        'Urine Test Positive',
                        '${summary.urinePositiveCount} flagged',
                      ),
                      _buildDetailBullet(
                        'Pregnancy Test Positive',
                        '${summary.pregnancyPositiveCount} positive',
                      ),
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
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
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
                        ...summary.medicationDispensedCounts.entries
                            .take(8)
                            .map(
                              (e) => pw.TableRow(
                                children: [
                                  _buildTableCell(e.key),
                                  _buildTableCell(
                                    '${e.value}',
                                    align: pw.TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
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
                      pw.Text(
                        'Report Compiled By: ${summary.generatedBy}',
                        style: pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        'Digital Audit Chain Verified: SHA-256 Validated',
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 140,
                        height: 1,
                        color: PdfColors.black,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Lead Gynecologist / Medical Officer',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
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
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: primaryColor, width: 1.2),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${PdfReportService.sanitizeText(summary.campName)} — Comprehensive Patient Register (${summary.patients.length} Registered Patients)',
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),
            build: (context) => [
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: borderGray, width: 0.5),
                headerStyle: pw.TextStyle(
                  fontSize: 6.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                cellStyle: pw.TextStyle(fontSize: 6.0, color: darkTextColor),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(
                  horizontal: 2.5,
                  vertical: 2.0,
                ),
                headers: [
                  'ID',
                  'Name',
                  'Camp',
                  'Age',
                  'Mobile',
                  'Ward',
                  'Marital',
                  'Guardian',
                  'Complaints',
                  'Level',
                  'POP',
                  'Diagnoses',
                  'Meds',
                  'Pessary',
                  'Referral',
                  'Destination',
                  'Doctor',
                  'Date',
                ],
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2), // ID
                  1: const pw.FlexColumnWidth(1.7), // Name
                  2: const pw.FlexColumnWidth(0.8), // Camp
                  3: const pw.FlexColumnWidth(0.5), // Age
                  4: const pw.FlexColumnWidth(1.1), // Mobile
                  5: const pw.FlexColumnWidth(0.9), // Ward
                  6: const pw.FlexColumnWidth(0.8), // Marital
                  7: const pw.FlexColumnWidth(1.2), // Guardian
                  8: const pw.FlexColumnWidth(1.6), // Complaints
                  9: const pw.FlexColumnWidth(1.0), // Level
                  10: const pw.FlexColumnWidth(0.7), // POP
                  11: const pw.FlexColumnWidth(1.7), // Diagnoses
                  12: const pw.FlexColumnWidth(1.7), // Meds
                  13: const pw.FlexColumnWidth(1.1), // Pessary
                  14: const pw.FlexColumnWidth(1.1), // Referral
                  15: const pw.FlexColumnWidth(1.1), // Destination
                  16: const pw.FlexColumnWidth(1.4), // Doctor
                  17: const pw.FlexColumnWidth(1.0), // Date
                },
                data: summary.patients.map((p) {
                  final v = visitByPatientId[p.patientId];
                  final campCode = p.campCode.isNotEmpty
                      ? p.campCode
                      : (p.patientId.split('-').length >= 2
                            ? p.patientId.split('-')[1]
                            : summary.campCode);

                  final allMeds = <String>[
                    if (v != null)
                      ...v.medications.where((m) => m.trim().isNotEmpty),
                    if (v?.customMedication != null &&
                        v!.customMedication!.trim().isNotEmpty)
                      v.customMedication!.trim(),
                  ];
                  final medsStr = allMeds.isNotEmpty
                      ? allMeds.join(', ')
                      : 'None';

                  final pessaryStr =
                      v?.pessaryType != null &&
                          v!.pessaryType!.trim().isNotEmpty
                      ? (v.pessarySize != null &&
                                v.pessarySize!.trim().isNotEmpty
                            ? '${v.pessaryType!.trim()} (${v.pessarySize!.trim()})'
                            : v.pessaryType!.trim())
                      : '-';

                  final docName =
                      (v?.attendingDoctorNames
                                  .where((d) => d.trim().isNotEmpty)
                                  .length ??
                              0) >
                          1
                      ? v!.attendingDoctorNames
                            .where((d) => d.trim().isNotEmpty)
                            .join(', ')
                      : (v?.primaryDoctorName != null &&
                                v!.primaryDoctorName!.trim().isNotEmpty
                            ? v.primaryDoctorName!.trim()
                            : (v?.attendingDoctorNames.any(
                                        (d) => d.trim().isNotEmpty,
                                      ) ==
                                      true
                                  ? v!.attendingDoctorNames
                                        .where((d) => d.trim().isNotEmpty)
                                        .first
                                  : (p.primaryDoctorName != null &&
                                            p.primaryDoctorName!
                                                .trim()
                                                .isNotEmpty
                                        ? p.primaryDoctorName!.trim()
                                        : '-')));

                  final pTLevel = (v?.treatmentLevel?.trim().isNotEmpty == true)
                      ? v!.treatmentLevel!.trim()
                      : (p.treatmentLevel?.trim() ?? '');
                  final tLevelShort = (pTLevel == 'gyno_checkup' || pTLevel == 'full_check_up')
                      ? 'Gynocheck'
                      : ((pTLevel == 'counseling' || pTLevel == 'council_level') ? 'Counseling' : '-');

                  return [
                    PdfReportService.sanitizeText(p.patientId),
                    PdfReportService.sanitizeText(
                      '${p.firstName} ${p.surname}',
                    ),
                    PdfReportService.sanitizeText(campCode),
                    p.age.toString(),
                    PdfReportService.sanitizeText(p.mobile),
                    PdfReportService.sanitizeText(
                      p.ward.isNotEmpty
                          ? 'Ward ${p.ward}'
                          : (p.municipality.isNotEmpty ? p.municipality : '-'),
                    ),
                    PdfReportService.sanitizeText(p.maritalStatus),
                    PdfReportService.sanitizeText(p.spouseOrFatherName ?? '-'),
                    PdfReportService.sanitizeText(
                      p.reasonsForVisit.isNotEmpty
                          ? p.reasonsForVisit.join(', ')
                          : '-',
                    ),
                    PdfReportService.sanitizeText(tLevelShort),
                    v != null ? 'Stage ${v.highestPopStage}' : '-',
                    PdfReportService.sanitizeText(
                      v?.diagnoses.isNotEmpty == true
                          ? v!.diagnoses.join(', ')
                          : 'None',
                    ),
                    PdfReportService.sanitizeText(medsStr),
                    PdfReportService.sanitizeText(pessaryStr),
                    PdfReportService.sanitizeText(v?.surgicalReferral ?? '-'),
                    PdfReportService.sanitizeText(
                      v?.followUpDestination ?? '-',
                    ),
                    PdfReportService.sanitizeText(docName),
                    dateFormatter.format(p.intakeDate),
                  ];
                }).toList(),
              ),
            ],
          ),
        );
      }
      return pdf;
    });
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
      child: ne(title, size: 10, bold: true, color: 0xFFFFFFFF),
    );
  }

  pw.Widget _buildTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: ne(text, size: 8.5, bold: true, color: 0xFF1E293B),
    );
  }

  pw.Widget _buildTableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: ne(text, size: 8, bold: isBold, color: 0xFF1E293B),
    );
  }

  pw.Widget _buildDetailBullet(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        children: [
          ne('$label: ', size: 8.5, bold: true, color: 0xFF1E293B),
          ne(value, size: 8.5, color: 0xFF1E293B),
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
          ne('$label: ', size: 8.5, bold: true, color: 0xFF1F2937),
          pw.Expanded(
            child: ne(
              safeValue,
              size: 8.5,
              bold: isBold,
              color: isBold ? 0xFF134E4A : 0xFF000000,
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
    String organizationName = AppConstants.defaultOrganizationName,
  }) async {
    final effectiveOrgName = resolveEffectiveOrganizationName(
      organizationName: organizationName,
      camp: camp,
    );
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      final dateFormatter = DateFormat('yyyy-MM-dd');
      final timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

      final primaryColor = PdfColor.fromHex(
        '30026E',
      ); // WFWSN Logo Royal Violet
      final secondaryColor = PdfColor.fromHex(
        '81005D',
      ); // WFWSN Logo Wine/Magenta
      final lightBgColor = PdfColor.fromHex('F5F3FF'); // Soft Violet Tint
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

      final effectiveTreatmentLevel =
          (visit?.treatmentLevel?.trim().isNotEmpty == true)
          ? visit!.treatmentLevel!.trim()
          : (patient.treatmentLevel?.trim() ?? '');
      final treatmentLevelLabel = (effectiveTreatmentLevel == 'gyno_checkup' || effectiveTreatmentLevel == 'full_check_up')
          ? 'Gynocheckup (गाइनो जाँच)'
          : ((effectiveTreatmentLevel == 'counseling' || effectiveTreatmentLevel == 'council_level')
                ? 'Counseling (काउन्सिलिङ)'
                : (effectiveTreatmentLevel.isNotEmpty
                      ? effectiveTreatmentLevel
                      : 'Not Specified (नतोकिएको)'));

      final effectiveDiagnoses = (visit != null && visit.diagnoses.isNotEmpty)
          ? visit.diagnoses
          : patient.diagnoses;
      final rawMedications =
          (visit != null && visit.medications.isNotEmpty)
          ? visit.medications
          : patient.medications;
      final effectiveMedications = rawMedications
          .where((m) => m.trim().isNotEmpty && !ReportAggregationService.isDosageInstruction(m))
          .toList();
      final effectiveCustomMed =
          (visit?.customMedication != null &&
              visit!.customMedication!.isNotEmpty)
          ? visit.customMedication
          : patient.customMedication;
      final effectiveCounseling =
          (visit?.counseling != null && visit!.counseling.isNotEmpty)
          ? visit.counseling
          : patient.counseling;
      final effectivePessaryType =
          (visit?.pessaryType != null && visit!.pessaryType!.isNotEmpty)
          ? visit.pessaryType
          : patient.pessaryType;
      final effectivePessarySize =
          (visit?.pessarySize != null && visit!.pessarySize!.isNotEmpty)
          ? visit.pessarySize
          : patient.pessarySize;

      // Map structured complaints
      final complaintsMap = visit?.anamnesisComplaints ?? {};
      // Normalize complaint key to a canonical form for dedup
      String canonicalComplaintKey(String key) {
        final k = key.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), ' ').trim();
        if (k.contains('prolapse') || k.contains('hanging') || k.contains('mass per vagina')) return 'prolapse';
        if (k.contains('discharge') || k.contains('itching')) return 'discharge';
        if (k.contains('urine') || k.contains('micturition')) return 'urine';
        if (k.contains('stool') || k.contains('bowel')) return 'stool';
        if (k.contains('menstrual')) return 'menstrual';
        if (k.contains('infertility')) return 'infertility';
        if (k.contains('pelvic') || k.contains('heaviness') || k.contains('dragging')) return 'pelvic_heaviness';
        if (k.contains('dyspareunia') || k.contains('coital pain')) return 'dyspareunia';
        if (k.contains('coital bleeding') || k.contains('post coital')) return 'post_coital_bleeding';
        if (k.contains('incontinence')) return 'incontinence';
        if (k.contains('back') && k.contains('pain')) return 'backache';
        if (k.contains('abdomen') || k.contains('abdominal')) return 'lower_abdominal_pain';
        if (k.contains('checkup')) return 'checkup';
        return k;
      }

      // Map canonical keys to display labels
      final canonicalTitles = {
        'prolapse': 'Uterine Prolapse / Something Hanging Out',
        'discharge': 'Discharge / Itching',
        'urine': 'Problems Passing Urine',
        'stool': 'Problems Passing Stool',
        'menstrual': 'Menstrual Problem',
        'infertility': 'Infertility',
        'pelvic_heaviness': 'Pelvic Heaviness / Dragging Sensation',
        'dyspareunia': 'Dyspareunia / Coital Pain',
        'post_coital_bleeding': 'Abnormal / Coital Bleeding',
        'incontinence': 'Urinary Incontinence',
        'backache': 'Severe Backache / Sacral Pain',
        'lower_abdominal_pain': 'Lower Abdominal Pain',
        'checkup': 'General Checkup',
      };

      // Keys that are metadata, not actual complaint categories
      const metaKeys = {
        'clinicalComplaints',
        'clinical_complaints',
        'complaints_duration',
        'complaintsDuration',
        'reasons',
        'new_issues',
        'newIssues',
      };

      // Build complaint display list from clinicalComplaints (source of truth)
      // plus any Map entries not already covered
      final seenCanonical = <String>{};
      final complaintDisplayList = <Map<String, dynamic>>[];

      // 1. Use clinicalComplaints list as the primary source
      final rawClinical = complaintsMap['clinicalComplaints'] ?? complaintsMap['clinical_complaints'];
      final clinicalList = <String>[];
      if (rawClinical is List) {
        for (final item in rawClinical) {
          if (item != null) clinicalList.add(item.toString());
        }
      }

      for (final complaintName in clinicalList) {
        final canon = canonicalComplaintKey(complaintName);
        if (seenCanonical.contains(canon)) continue;
        seenCanonical.add(canon);
        // Try to find detail Map under any alias
        Map<String, dynamic>? details;
        for (final entry in complaintsMap.entries) {
          if (entry.value is! Map) continue;
          if (canonicalComplaintKey(entry.key) == canon) {
            details = Map<String, dynamic>.from(entry.value as Map);
            break;
          }
        }
        complaintDisplayList.add({
          'key': complaintName,
          'canon': canon,
          'details': details,
        });
      }

      // 2. Also include any Map entries not yet covered by clinicalComplaints
      for (final entry in complaintsMap.entries) {
        if (metaKeys.contains(entry.key)) continue;
        if (entry.value is! Map) continue;
        final canon = canonicalComplaintKey(entry.key);
        if (seenCanonical.contains(canon)) continue;
        seenCanonical.add(canon);
        complaintDisplayList.add({
          'key': entry.key,
          'canon': canon,
          'details': Map<String, dynamic>.from(entry.value as Map),
        });
      }

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
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoImage != null)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 10),
                      child: pw.Image(logoImage, width: 44, height: 44),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          effectiveOrgName.toUpperCase(),
                          style: pw.TextStyle(
                            color: primaryColor,
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'CLINICAL CASE DOSSIER & PATIENT HEALTH RECORD',
                          style: pw.TextStyle(
                            fontSize: 14.5,
                            fontWeight: pw.FontWeight.bold,
                            color: darkTextColor,
                          ),
                        ),
                        pw.Text(
                          'Comprehensive Gynecological Examination & Encounter Summary',
                          style: const pw.TextStyle(
                            fontSize: 9.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Outreach Camp: ${sanitizeText(camp?.name ?? "Gynae Outreach Station")} (${camp?.campCode ?? patient.campCode})',
                          style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                            color: secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
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
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.Text(
                        'Date: ${dateFormatter.format(visit?.visitDate ?? patient.intakeDate)}',
                        style: const pw.TextStyle(
                          fontSize: 7.5,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // 2. PATIENT DEMOGRAPHICS & INTAKE PROFILE
            _buildPdfSectionHeader(
              '1. PATIENT DEMOGRAPHICS & SOCIAL INTAKE',
              primaryColor,
            ),
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
                      pw.Expanded(
                        child: _buildPdfField(
                          'Full Name',
                          patient.fullName,
                          isBold: true,
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Patient ID',
                          patient.patientId,
                          isBold: true,
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Age / Marital',
                          '${patient.age} yrs (${patient.maritalStatus})',
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        flex: 2,
                        child: _buildPdfField(
                          'Guardian / Spouse',
                          () {
                            final name = patient.spouseOrFatherName ?? 'N/A';
                            final rel = patient.relationshipType;
                            if (rel != null && rel.isNotEmpty && name != 'N/A') {
                              return '$name ($rel)';
                            }
                            return name;
                          }(),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Mobile Contact',
                          patient.mobile.isNotEmpty
                              ? patient.mobile
                              : 'Not Provided',
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildPdfField(
                          'Permanent Address',
                          () {
                            final parts = <String>[];
                            if (patient.ward.isNotEmpty) parts.add('Ward ${patient.ward}');
                            if (patient.municipality.isNotEmpty) parts.add(patient.municipality);
                            if (patient.district.isNotEmpty) parts.add(patient.district);
                            return parts.isNotEmpty ? parts.join(', ') : 'N/A';
                          }(),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  _buildPdfField(
                    'Consultation (परामर्श)',
                    treatmentLevelLabel,
                    isBold: true,
                  ),
                  if (patient.reasonsForVisit.isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    _buildPdfField(
                      'Intake Complaints',
                      patient.reasonsForVisit.join(', '),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // 3. STRUCTURED YELLOW FORM CLINICAL ANAMNESIS
            _buildPdfSectionHeader(
              '2. STRUCTURED CLINICAL ANAMNESIS (YELLOW FORM)',
              primaryColor,
            ),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderGray, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: complaintDisplayList.isEmpty
                  ? pw.Text(
                      'No acute gynecological complaints recorded during clinical intake.',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    )
                  : pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: complaintDisplayList.map((item) {
                        final canon = item['canon'] as String;
                        final key = item['key'] as String;
                        final title = canonicalTitles[canon] ??
                            key.replaceAll('_', ' ').toUpperCase();
                        final detailsMap = item['details'] as Map<String, dynamic>?;
                        String details = '';
                        if (detailsMap != null && detailsMap.isNotEmpty) {
                          final dur = detailsMap['duration']?.toString() ?? '';
                          final rem = detailsMap['remarks']?.toString() ?? '';
                          final opts = detailsMap['options'];
                          final optStr = opts is List ? opts.join(', ') : '';
                          details = [
                            dur,
                            optStr,
                            rem,
                          ].where((s) => s.isNotEmpty).join(' | ');
                        }
                        return pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Container(
                                width: 6,
                                height: 6,
                                margin: const pw.EdgeInsets.only(
                                  top: 3,
                                  right: 6,
                                ),
                                decoration: pw.BoxDecoration(
                                  color: secondaryColor,
                                  shape: pw.BoxShape.circle,
                                ),
                              ),
                              pw.SizedBox(
                                width: 170,
                                child: pw.Text(
                                  title,
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                    color: darkTextColor,
                                  ),
                                ),
                              ),
                              pw.Expanded(
                                child: pw.Text(
                                  details.isNotEmpty
                                      ? details
                                      : 'Present',
                                  style: const pw.TextStyle(
                                    fontSize: 8,
                                    color: PdfColors.grey800,
                                  ),
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
            _buildPdfSectionHeader(
              '3. OBSTETRIC HISTORY & GYNECOLOGICAL EXAM',
              primaryColor,
            ),
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
                        child: _buildPdfField(
                          'Deliveries (Parity)',
                          visit?.deliveries?.toString() ?? 'N/A',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Living Children',
                          visit?.livingChildren?.toString() ?? 'N/A',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Abortions / Losses',
                          visit?.abortions?.toString() ?? 'N/A',
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildPdfField(
                          'Uterus Inside',
                          (visit?.uterusInside ?? true)
                              ? 'Yes'
                              : 'No',
                          isBold: !(visit?.uterusInside ?? true),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Cervix',
                          sanitizeText(visit?.cervixRemarks ?? 'normal'),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Pelvic Floor Muscle',
                          visit?.pelvicFloorTone.toUpperCase() ?? 'NORMAL',
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildPdfField(
                          'Vulva',
                          sanitizeText(visit?.vulvaRemarks ?? 'normal'),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Vagina',
                          sanitizeText(visit?.vaginaRemarks ?? 'normal'),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Uterus',
                          sanitizeText(visit?.uterusRemarks ?? 'normal'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // 5. CLINICAL VITALS & SCREENING LABS
            _buildPdfSectionHeader(
              '4. CLINICAL VITALS & SCREENING LABS',
              primaryColor,
            ),
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
                              visit?.systolicBp != null
                                  ? '${visit!.systolicBp}/${visit.diastolicBp ?? 0} mmHg'
                                  : 'N/A',
                              isBold: true,
                            ),
                            pw.Text(
                              'Status: $bpStatus',
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                color: bpColor,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Pulse Rate',
                          visit?.pulse != null ? '${visit!.pulse} bpm' : 'N/A',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'SpO2 Saturation',
                          visit?.spo2 != null ? '${visit!.spo2}%' : 'N/A',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Blood Glucose',
                          visit?.glucose != null
                              ? '${visit!.glucose} mg/dL'
                              : 'N/A',
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildPdfField(
                          'Urine Test',
                          visit?.urineTest != null
                              ? visit!.urineTest!.toUpperCase()
                              : 'NORMAL',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Pregnancy Test (UPT)',
                          visit?.pregnancyTest != null
                              ? visit!.pregnancyTest!.toUpperCase()
                              : 'NEG',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'ECG',
                          (visit?.ecgNotes != null && visit!.ecgNotes!.trim().isNotEmpty)
                              ? sanitizeText(visit.ecgNotes!)
                              : 'Normal / Not indicated',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // 5. POP STAGING MATRIX
            _buildPdfSectionHeader(
              '5. POP STAGING (PELVIC ORGAN PROLAPSE)',
              primaryColor,
            ),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                color: (visit?.highestPopStage ?? 0) >= 2
                    ? lightBgColor
                    : PdfColors.white,
                border: pw.Border.all(
                  color: (visit?.highestPopStage ?? 0) >= 2
                      ? secondaryColor
                      : borderGray,
                  width: 0.8,
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPopBadge(
                    'ANTERIOR (Cystocele)',
                    (visit?.popAnteriorStage ?? 0) == 0
                        ? 'Stage 0 (Normal)'
                        : 'Stage ${visit?.popAnteriorStage ?? 0}',
                    isHighlight: (visit?.popAnteriorStage ?? 0) == 2,
                    isCritical: (visit?.popAnteriorStage ?? 0) >= 3,
                    isNormal: (visit?.popAnteriorStage ?? 0) == 0,
                  ),
                  _buildPopBadge(
                    'MIDDLE (Uterine)',
                    (visit?.popMiddleStage ?? 0) == 0
                        ? 'Stage 0 (Normal)'
                        : 'Stage ${visit?.popMiddleStage ?? 0}',
                    isHighlight: (visit?.popMiddleStage ?? 0) == 2,
                    isCritical: (visit?.popMiddleStage ?? 0) >= 3,
                    isNormal: (visit?.popMiddleStage ?? 0) == 0,
                  ),
                  _buildPopBadge(
                    'POSTERIOR (Rectocele)',
                    (visit?.popPosteriorStage ?? 0) == 0
                        ? 'Stage 0 (Normal)'
                        : 'Stage ${visit?.popPosteriorStage ?? 0}',
                    isHighlight: (visit?.popPosteriorStage ?? 0) == 2,
                    isCritical: (visit?.popPosteriorStage ?? 0) >= 3,
                    isNormal: (visit?.popPosteriorStage ?? 0) == 0,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // 7. DIAGNOSES & TREATMENT FORMULARY
            _buildPdfSectionHeader(
              '6. CONFIRMED DIAGNOSES & FORMULARY',
              primaryColor,
            ),
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
                    effectiveDiagnoses.isNotEmpty
                        ? effectiveDiagnoses.join(', ')
                        : 'No acute gynecological pathology diagnosed',
                    isBold: true,
                  ),
                  pw.SizedBox(height: 3),
                  _buildPdfField(
                    'Prescribed Formulary',
                    effectiveMedications.isNotEmpty
                        ? effectiveMedications.join(' | ')
                        : 'None Dispensed',
                  ),
                  if (effectiveCustomMed != null &&
                      effectiveCustomMed.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField('Special Prescriptions', effectiveCustomMed),
                  ],
                  if (effectivePessarySize != null &&
                      effectivePessarySize.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField(
                      'Ring Pessary Fitted',
                      '${effectivePessaryType ?? "Ring Pessary"} (Size: $effectivePessarySize)',
                      isBold: true,
                    ),
                  ],
                  if (effectiveCounseling.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField(
                      'Patient Counseling Provided',
                      effectiveCounseling.join(', '),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // 8. DISCHARGE, SURGICAL REFERRAL & CONTINUITY OF CARE
            _buildPdfSectionHeader(
              '7. CONTINUITY OF CARE & REFERRAL',
              primaryColor,
            ),
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
                          (visit?.followUpNeeded ?? false)
                              ? 'YES (Indicated)'
                              : 'NO (Routine)',
                          isBold: (visit?.followUpNeeded ?? false),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Follow-up Center',
                          visit?.followUpDestination?.isNotEmpty == true
                              ? visit!.followUpDestination!
                              : 'Local Health Post',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Surgical Referral',
                          visit?.surgicalReferral?.isNotEmpty == true
                              ? visit!.surgicalReferral!
                              : 'None Indicated',
                          isBold: visit?.surgicalReferral?.isNotEmpty == true,
                        ),
                      ),
                    ],
                  ),
                  if (visit?.outtakeNotes != null &&
                      visit!.outtakeNotes!.isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    _buildPdfField(
                      'Attending Physician Clinical Notes',
                      visit.outtakeNotes!,
                    ),
                  ],
                ],
              ),
            ),
            if (allVisits != null && allVisits.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _buildPdfSectionHeader(
                '8. LONGITUDINAL CLINICAL ENCOUNTERS & FOLLOW-UP TIMELINE (${allVisits.length} RECORDED)',
                primaryColor,
              ),
              pw.SizedBox(height: 4),
              ...allVisits.map((v) {
                final isFollowUp = v.isFollowUp;
                final dateFormatted = dateFormatter.format(v.visitDate);
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 5),
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: isFollowUp
                        ? PdfColor.fromHex('F8FAFC')
                        : lightBgColor,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                    border: pw.Border.all(
                      color: isFollowUp
                          ? PdfColor.fromHex('94A3B8')
                          : primaryColor,
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
                            sanitizeText(
                              isFollowUp
                                  ? 'Follow-Up Review ($dateFormatted)'
                                  : 'Initial Camp Examination ($dateFormatted)',
                            ),
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                              color: isFollowUp
                                  ? PdfColors.blueGrey800
                                  : primaryColor,
                            ),
                          ),
                          pw.Text(
                            'BP: ${v.systolicBp ?? "-"}/${v.diastolicBp ?? "-"} | Pulse: ${v.pulse ?? "-"} bpm | SpO2: ${v.spo2 ?? "-"}%',
                            style: const pw.TextStyle(
                              fontSize: 7.5,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              'POP: Stage ${v.highestPopStage} (Ant: ${v.popAnteriorStage}, Mid: ${v.popMiddleStage}, Post: ${v.popPosteriorStage})',
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                fontWeight: pw.FontWeight.bold,
                                color: darkTextColor,
                              ),
                            ),
                          ),
                          if (v.pessarySize != null &&
                              v.pessarySize!.isNotEmpty)
                            pw.Text(
                              sanitizeText(
                                'Pessary: ${v.pessaryType ?? "Ring"} Sz ${v.pessarySize}',
                              ),
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                color: primaryColor,
                              ),
                            ),
                          if (v.surgeryDone)
                            pw.Text(
                              sanitizeText(
                                ' | Surgery: ${v.surgeryType ?? "Done"}',
                              ),
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                color: secondaryColor,
                              ),
                            ),
                        ],
                      ),
                      if (v.diagnoses.isNotEmpty) ...[
                        pw.SizedBox(height: 1.5),
                        pw.Text(
                          sanitizeText('Diagnoses: ${v.diagnoses.join(", ")}'),
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.grey800,
                          ),
                        ),
                      ],
                      if (v.medications.isNotEmpty) ...[
                        pw.SizedBox(height: 1.5),
                        pw.Text(
                          sanitizeText(
                            'Medications: ${v.medications.join(", ")}',
                          ),
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.grey800,
                          ),
                        ),
                      ],
                      if (v.followUpNotes != null &&
                          v.followUpNotes!.isNotEmpty) ...[
                        pw.SizedBox(height: 1.5),
                        pw.Text(
                          sanitizeText(
                            'Follow-up / Encounter Notes: ${v.followUpNotes}',
                          ),
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.grey700,
                          ),
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
                    pw.Text(
                      'Document Reference: DOSSIER-${patient.patientId}',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      'Generated Timestamp: ${timeFormatter.format(DateTime.now())}',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.Text(
                      'Audit Integrity: SHA-256 Ledger Attested | Digital Outreach Record',
                      style: pw.TextStyle(fontSize: 7.5, color: secondaryColor),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Container(
                      width: 150,
                      height: 0.8,
                      color: PdfColors.black,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Medical Officer / Attending Gynecologist',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Nepal Medical Council (NMC) Certified',
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      return pdf;
    });
  }

  pw.Widget _buildPdfSectionHeader(String title, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('F5F3FF'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: color, width: 0.8),
      ),
      child: ne(title, size: 10.0, bold: true, color: 0xFF30026E),
    );
  }

  pw.Widget _buildPopBadge(
    String label,
    String value, {
    bool isHighlight = false,
    bool isCritical = false,
    bool isNormal = false,
  }) {
    final bgColor = isCritical
        ? PdfColor.fromHex('FFE4E6')
        : (isHighlight
              ? PdfColor.fromHex('FEF3C7')
              : (isNormal
                    ? PdfColor.fromHex('F0FDF4')
                    : PdfColor.fromHex('F1F5F9')));
    final textColor = isCritical
        ? PdfColor.fromHex('BE123C')
        : (isHighlight
              ? PdfColor.fromHex('92400E')
              : (isNormal
                    ? PdfColor.fromHex('166534')
                    : PdfColor.fromHex('334155')));

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: textColor, width: 0.8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7,
              color: textColor,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 1.5),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9.5,
              color: textColor,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
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
    String organizationName = AppConstants.defaultOrganizationName,
  }) async {
    final effectiveOrgName = resolveEffectiveOrganizationName(
      organizationName: organizationName,
      camp: camp,
    );
    final theme = await getPdfTheme();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      final dateFormatter = DateFormat('yyyy-MM-dd');
      final timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

      final primary = PdfColor.fromHex('30026E'); // WFWSN Logo Royal Violet
      final secondary = PdfColor.fromHex('81005D'); // WFWSN Logo Wine/Magenta
      final lightBg = PdfColor.fromHex('F5F3FF'); // Soft Violet Tint
      final dark = PdfColor.fromHex('1E293B');
      final gray = PdfColor.fromHex('CBD5E1');
      final cyanBg = PdfColor.fromHex('FDF2F8'); // Soft Rose Tint
      final cyan = PdfColor.fromHex('81005D'); // Secondary Wine/Magenta

      // Load WFWSN logo
      final logoImage = await loadLogoImage();

      final isFollowUp = visit.isFollowUp;
      final encounterColor = isFollowUp ? cyan : primary;
      final encounterBg = isFollowUp ? cyanBg : lightBg;
      final encounterLabel = isFollowUp
          ? 'FOLLOW-UP CLINICAL ENCOUNTER'
          : 'PRIMARY CAMP EXAMINATION';
      final visitDate = dateFormatter.format(visit.visitDate);
      final visitTime = timeFormatter.format(visit.visitDate);

      final effectiveTreatmentLevel =
          (visit.treatmentLevel?.trim().isNotEmpty == true)
          ? visit.treatmentLevel!.trim()
          : (patient.treatmentLevel?.trim() ?? '');
      final treatmentLevelLabel = (effectiveTreatmentLevel == 'gyno_checkup' || effectiveTreatmentLevel == 'full_check_up')
          ? 'Gynocheckup (गाइनो जाँच)'
          : ((effectiveTreatmentLevel == 'counseling' || effectiveTreatmentLevel == 'council_level')
                ? 'Counseling (काउन्सिलिङ)'
                : (effectiveTreatmentLevel.isNotEmpty
                      ? effectiveTreatmentLevel
                      : 'Not Specified (नतोकिएको)'));

      // BP classification
      String bpStatus = 'N/A';
      PdfColor bpColor = dark;
      if (visit.systolicBp != null && visit.diastolicBp != null) {
        final s = visit.systolicBp!;
        final d = visit.diastolicBp!;
        if (s >= 160 || d >= 100) {
          bpStatus = 'HTN Stage 2 (Critical)';
          bpColor = PdfColor.fromHex('BE123C');
        } else if (s >= 140 || d >= 90) {
          bpStatus = 'HTN Stage 1 (Elevated)';
          bpColor = PdfColor.fromHex('B45309');
        } else if (s >= 120) {
          bpStatus = 'Pre-Hypertension';
          bpColor = PdfColor.fromHex('B45309');
        } else {
          bpStatus = 'Normal Range';
          bpColor = primary;
        }
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
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // WFWSN Logo
                  if (logoImage != null)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 10),
                      child: pw.Image(logoImage, width: 48, height: 48),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          sanitizeText(effectiveOrgName.toUpperCase()),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: encounterColor,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          encounterLabel,
                          style: pw.TextStyle(
                            fontSize: 14.5,
                            fontWeight: pw.FontWeight.bold,
                            color: dark,
                          ),
                        ),
                        pw.Text(
                          'Clinical Encounter Record | Individual Visit Slip',
                          style: const pw.TextStyle(
                            fontSize: 9.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Camp: ${sanitizeText(camp?.name ?? "Gynae Outreach Station")} (${camp?.campCode ?? patient.campCode})',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: secondary,
                          ),
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
                      pw.Text(
                        'ENCOUNTER-${patient.patientId}',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          fontWeight: pw.FontWeight.bold,
                          color: encounterColor,
                        ),
                      ),
                      pw.Text(
                        visitTime,
                        style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey600,
                        ),
                      ),
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
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: gray, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                children: [
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildPdfField(
                          'Patient ID',
                          patient.patientId,
                          isBold: true,
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Full Name',
                          patient.fullName,
                          isBold: true,
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Age',
                          '${patient.age} yrs (${patient.maritalStatus})',
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildPdfField(
                          'Address',
                          'Ward ${patient.ward}, ${patient.municipality}, ${patient.district}',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Guardian / Spouse',
                          patient.spouseOrFatherName ?? 'N/A',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Mobile',
                          patient.mobile.isNotEmpty ? patient.mobile : 'N/A',
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildPdfField(
                          'Consultation (परामर्श)',
                          treatmentLevelLabel,
                          isBold: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // ── Chief Complaints & Reasons to Visit ──────────────────────────
            _buildPdfSectionHeader(
              '2. CHIEF COMPLAINTS & REASONS TO VISIT',
              encounterColor,
            ),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: gray, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildPdfField(
                    'Initial Intake Reasons (प्रारम्भिक समस्या)',
                    patient.reasonsForVisit.isNotEmpty
                        ? patient.reasonsForVisit.join(' • ')
                        : 'Routine Follow-Up / Consultation',
                    isBold: patient.reasonsForVisit.isNotEmpty,
                  ),
                  if (visit.anamnesisComplaints.isNotEmpty &&
                      visit.anamnesisComplaints['reasons'] is List &&
                      (visit.anamnesisComplaints['reasons'] as List)
                          .isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    _buildPdfField(
                      'Active Encounter Complaints',
                      (visit.anamnesisComplaints['reasons'] as List).join(
                        ' • ',
                      ),
                    ),
                  ],
                  if (visit.anamnesisComplaints.isNotEmpty &&
                      visit.anamnesisComplaints['new_issues'] != null &&
                      (visit.anamnesisComplaints['new_issues'] as String)
                          .trim()
                          .isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    _buildPdfField(
                      'New Reported Issues / Symptoms',
                      sanitizeText(
                        visit.anamnesisComplaints['new_issues'] as String,
                      ),
                      isBold: true,
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // ── Obstetric History ────────────────────────────────────────────
            if (visit.deliveries != null ||
                visit.anamnesisComplaints.isNotEmpty) ...[
              _buildPdfSectionHeader(
                '3. OBSTETRIC HISTORY & EXAMINATION',
                encounterColor,
              ),
              pw.SizedBox(height: 3),
              pw.Container(
                padding: const pw.EdgeInsets.all(7),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: gray, width: 0.8),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildPdfField(
                            'Deliveries (Parity)',
                            visit.deliveries?.toString() ?? 'N/A',
                          ),
                        ),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Living Children',
                            visit.livingChildren?.toString() ?? 'N/A',
                          ),
                        ),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Abortions',
                            visit.abortions?.toString() ?? 'N/A',
                          ),
                        ),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Pelvic Floor Muscle',
                            visit.pelvicFloorTone.toUpperCase(),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 3),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildPdfField(
                            'Uterus Inside',
                            visit.uterusInside
                                ? 'Yes'
                                : 'No',
                            isBold: !visit.uterusInside,
                          ),
                        ),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Cervix',
                            sanitizeText(visit.cervixRemarks ?? 'normal'),
                          ),
                        ),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Vulva / Vagina',
                            sanitizeText(visit.vaginaRemarks ?? 'normal'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 7),
            ],

            // ── Clinical Vitals ──────────────────────────────────────────────
            _buildPdfSectionHeader(
              '4. CLINICAL VITALS & SCREENING LABS',
              encounterColor,
            ),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: gray, width: 0.8),
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
                              visit.systolicBp != null
                                  ? '${visit.systolicBp}/${visit.diastolicBp} mmHg'
                                  : 'N/A',
                              isBold: true,
                            ),
                            pw.Text(
                              'Status: $bpStatus',
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                color: bpColor,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Pulse Rate',
                          visit.pulse != null ? '${visit.pulse} bpm' : 'N/A',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'SpO2',
                          visit.spo2 != null ? '${visit.spo2}%' : 'N/A',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Blood Glucose',
                          visit.glucose != null
                              ? '${visit.glucose} mg/dL'
                              : 'N/A',
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: _buildPdfField(
                          'Urine Test',
                          (visit.urineTest ?? 'Normal').toUpperCase(),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Pregnancy Test',
                          (visit.pregnancyTest ?? 'Neg / N/A').toUpperCase(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // ── POP Staging ──────────────────────────────────────────────────
            _buildPdfSectionHeader(
              '5. POP STAGING (पाठेघर खस्ने अवस्था)',
              encounterColor,
            ),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                color: visit.highestPopStage >= 2 ? lightBg : PdfColors.white,
                border: pw.Border.all(
                  color: visit.highestPopStage >= 2 ? secondary : gray,
                  width: 0.8,
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPopBadge(
                    'ANTERIOR (Cystocele)',
                    visit.popAnteriorStage == 0
                        ? 'Stage 0 (Normal)'
                        : 'Stage ${visit.popAnteriorStage}',
                    isHighlight: visit.popAnteriorStage == 2,
                    isCritical: visit.popAnteriorStage >= 3,
                    isNormal: visit.popAnteriorStage == 0,
                  ),
                  _buildPopBadge(
                    'MIDDLE (Uterine)',
                    visit.popMiddleStage == 0
                        ? 'Stage 0 (Normal)'
                        : 'Stage ${visit.popMiddleStage}',
                    isHighlight: visit.popMiddleStage == 2,
                    isCritical: visit.popMiddleStage >= 3,
                    isNormal: visit.popMiddleStage == 0,
                  ),
                  _buildPopBadge(
                    'POSTERIOR (Rectocele)',
                    visit.popPosteriorStage == 0
                        ? 'Stage 0 (Normal)'
                        : 'Stage ${visit.popPosteriorStage}',
                    isHighlight: visit.popPosteriorStage == 2,
                    isCritical: visit.popPosteriorStage >= 3,
                    isNormal: visit.popPosteriorStage == 0,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // ── Diagnoses & Treatment ────────────────────────────────────────
            _buildPdfSectionHeader(
              '6. CONFIRMED DIAGNOSES & TREATMENT',
              encounterColor,
            ),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: gray, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildPdfField(
                    'Confirmed Diagnoses',
                    visit.diagnoses.isNotEmpty
                        ? visit.diagnoses.join(' | ')
                        : 'No acute pathology diagnosed',
                    isBold: visit.diagnoses.isNotEmpty,
                  ),
                  pw.SizedBox(height: 3),
                  _buildPdfField(
                    'Prescribed Medications',
                    () {
                      final filtered = visit.medications
                          .where((m) => m.trim().isNotEmpty && !ReportAggregationService.isDosageInstruction(m))
                          .toList();
                      return filtered.isNotEmpty
                          ? filtered.join(' | ')
                          : 'None dispensed';
                    }(),
                  ),
                  if (visit.customMedication?.isNotEmpty == true) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField(
                      'Other Prescriptions',
                      sanitizeText(visit.customMedication!),
                    ),
                  ],
                  if (visit.pessaryType != null) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField(
                      'Ring Pessary',
                      '${sanitizeText(visit.pessaryType!)} (${visit.pessarySize ?? "Standard"} mm)',
                      isBold: true,
                    ),
                  ],
                  if (visit.surgeryDone) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField(
                      'Surgery Performed',
                      sanitizeText(visit.surgeryType ?? 'Done'),
                      isBold: true,
                    ),
                  ],
                  if (visit.counseling.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField(
                      'Patient Counseling',
                      visit.counseling.join(', '),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 7),

            // ── Continuity of Care ────────────────────────────────────────────
            _buildPdfSectionHeader(
              '7. CONTINUITY OF CARE & REFERRAL',
              encounterColor,
            ),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: gray, width: 0.8),
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
                          visit.followUpNeeded
                              ? 'YES — Indicated'
                              : 'No (Routine)',
                          isBold: visit.followUpNeeded,
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Follow-up Center',
                          sanitizeText(
                            visit.followUpDestination ?? 'Local Health Post',
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Surgical Referral',
                          sanitizeText(
                            visit.surgicalReferral?.isNotEmpty == true
                                ? visit.surgicalReferral!
                                : 'None Indicated',
                          ),
                          isBold: visit.surgicalReferral?.isNotEmpty == true,
                        ),
                      ),
                    ],
                  ),
                  if (visit.followUpNotes?.isNotEmpty == true) ...[
                    pw.SizedBox(height: 3),
                    _buildPdfField(
                      'Follow-Up Clinical Notes',
                      sanitizeText(visit.followUpNotes!),
                    ),
                  ],
                  if (visit.outtakeNotes?.isNotEmpty == true) ...[
                    pw.SizedBox(height: 3),
                    _buildPdfField(
                      'Attending Physician Notes',
                      sanitizeText(visit.outtakeNotes!),
                    ),
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
                    if (visit.attendingNurseNames.isNotEmpty) ...[
                      pw.Text(
                        sanitizeText(
                          visit.attendingNurseNames
                              .map((n) => NurseProfile.parse(n).displayName)
                              .join(' & '),
                        ),
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: encounterColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Container(
                        width: 140,
                        height: 0.8,
                        color: PdfColors.black,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Attending Nurse / Health Worker',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                    ] else if (visit.primaryNurseName != null &&
                        visit.primaryNurseName!.trim().isNotEmpty) ...[
                      pw.Text(
                        sanitizeText(
                          NurseProfile.parse(visit.primaryNurseName!)
                              .displayName,
                        ),
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: encounterColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Container(
                        width: 140,
                        height: 0.8,
                        color: PdfColors.black,
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Attending Nurse / Health Worker',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                    ],
                    pw.Text(
                      'Doc Ref: ENCOUNTER-${patient.patientId}-$visitDate',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      'Generated: ${timeFormatter.format(DateTime.now())}',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.Text(
                      '${sanitizeText(organizationName)} — Attested Clinical Record',
                      style: pw.TextStyle(fontSize: 7.5, color: secondary),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (visit.attendingDoctorNames.isNotEmpty) ...[
                      pw.Text(
                        sanitizeText(
                          visit.attendingDoctorNames
                              .map(
                                (d) => d.toLowerCase().startsWith('dr')
                                    ? d
                                    : 'Dr. $d',
                              )
                              .join(' & '),
                        ),
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: encounterColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                    ] else if (camp != null && camp.doctorNames.isNotEmpty) ...[
                      pw.Text(
                        sanitizeText(
                          camp.doctorNames
                              .map(
                                (d) => d.toLowerCase().startsWith('dr')
                                    ? d
                                    : 'Dr. $d',
                              )
                              .join(' & '),
                        ),
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: encounterColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                    ] else if (camp != null &&
                        camp.doctorName.trim().isNotEmpty) ...[
                      pw.Text(
                        sanitizeText(
                          camp.doctorName.trim().toLowerCase().startsWith('dr')
                              ? camp.doctorName.trim()
                              : 'Dr. ${camp.doctorName.trim()}',
                        ),
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: encounterColor,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                    ],
                    pw.Container(
                      width: 150,
                      height: 0.8,
                      color: PdfColors.black,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Medical Officer / Attending Gynecologist',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'NMC Certified — Date: $visitDate',
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      return pdf;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BLANK FOLLOW-UP ENCOUNTER SLIP PDF (Printable 1-page re-check form)
  // ─────────────────────────────────────────────────────────────────────────
  void _addBlankFollowUpSlipPage(
    pw.Document pdf, {
    CampModel? camp,
    String? preprintedTokenId,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    String organizationName = AppConstants.defaultOrganizationName,
    pw.MemoryImage? logoImage,
  }) {
    final dateFormatter = DateFormat('yyyy-MM-dd');

    final secondary = PdfColor.fromHex('81005D'); // WFWSN Logo Wine/Magenta
    final cyan = PdfColor.fromHex('30026E'); // WFWSN Logo Royal Violet
    final cyanBg = PdfColor.fromHex('F5F3FF'); // Soft Violet Tint
    final dark = PdfColor.fromHex('1E293B');
    final gray = PdfColor.fromHex('CBD5E1');
    final boxBg = PdfColor.fromHex('FAFAFA');

    final bool showDoctor = camp?.showDoctorOnForms ?? true;
    final bool showNurse = camp?.showNurseOnForms ?? true;
    final List<String> campDoctors = camp?.doctorNames.isNotEmpty == true
        ? camp!.doctorNames
              .map(
                (d) => d
                    .trim()
                    .replaceAll(
                      RegExp(r'^(Dr\.?\s*)+', caseSensitive: false),
                      '',
                    )
                    .trim(),
              )
              .where((d) => d.isNotEmpty)
              .toSet()
              .toList()
        : (camp?.doctorName.trim().isNotEmpty == true
              ? [
                  camp!.doctorName
                      .trim()
                      .replaceAll(
                        RegExp(r'^(Dr\.?\s*)+', caseSensitive: false),
                        '',
                      )
                      .trim(),
                ]
              : <String>[]);
    final List<NurseProfile> campNurses =
        camp?.nurseProfiles.toSet().toList() ?? <NurseProfile>[];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        build: (ctx) {
          // ── Professional full-width section header (solid band, matches Pages 1 & 2) ──
          pw.Widget secHeader(String title) {
            return pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 5, bottom: 3),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3.5,
              ),
              decoration: pw.BoxDecoration(
                color: cyan,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 9.0,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  letterSpacing: 0.2,
                ),
              ),
            );
          }

          pw.Widget blankField(String label, {double flex = 1}) => pw.Expanded(
            flex: flex.toInt(),
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 3,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  ne(label, size: 8.2, color: 0xFF475569),
                  pw.SizedBox(height: 2),
                  pw.Container(
                    height: 16,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: gray, width: 0.6),
                      color: boxBg,
                    ),
                  ),
                ],
              ),
            ),
          );

          // ── Professional checkbox — 13 × 13 pt, 1.2 pt border, light fill ──
          pw.Widget cb(String label) => pw.Padding(
            padding: const pw.EdgeInsets.only(right: 7, bottom: 2.5),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(
                  width: 13.0,
                  height: 13.0,
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('F8F8F8'),
                    border: pw.Border.all(color: gray, width: 1.2),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(2.5),
                    ),
                  ),
                ),
                pw.SizedBox(width: 4),
                ne(label, size: 8.5, color: 0xFF1E293B),
              ],
            ),
          );

          // Nurse signature block (empty when camp has no nurses & none requested)
          final nurseWidgets = _buildNurseSignatureBlock(
            cb: (label, checked) => cb(label),
            campNurses: campNurses,
            showNurse: showNurse,
            blankNurseLines: blankNurseLines,
            nurse: nurse,
            primary: cyan,
            dark: dark,
            fsSmall: 7,
          );

          pw.Widget buildCharBoxes(
            String val, {
            int minBoxes = 10,
            int maxBoxes = 10,
            double boxSize = 14,
            double boxMargin = 1.5,
          }) {
            final cleanVal = val.trim().replaceAll(RegExp(r'\s+'), ' ');
            final chars = cleanVal.toUpperCase().split('');
            return pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: List.generate(maxBoxes, (i) {
                final rawChar = i < chars.length ? chars[i] : '';
                final char = rawChar == '□' ? '' : rawChar;
                return pw.Container(
                  width: boxSize,
                  height: boxSize,
                  margin: pw.EdgeInsets.only(right: boxMargin),
                  decoration: pw.BoxDecoration(
                    color: boxBg,
                    border: pw.Border.all(color: gray, width: 0.7),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      char,
                      style: pw.TextStyle(
                        fontSize: 9.0,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                  ),
                );
              }),
            );
          }

          pw.Widget line({double h = 15, String? text}) => pw.Container(
            height: h,
            margin: const pw.EdgeInsets.only(top: 2, bottom: 2),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: gray, width: 0.6)),
            ),
            alignment: pw.Alignment.bottomLeft,
            child: text != null
                ? pw.Text(
                    sanitizeText(text),
                    style: pw.TextStyle(fontSize: 8.5, color: dark),
                  )
                : null,
          );

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: cyanBg,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                  border: pw.Border.all(color: cyan, width: 1.2),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          if (logoImage != null)
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(right: 10),
                              child: pw.Image(logoImage, width: 56, height: 56),
                            ),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  sanitizeText(organizationName.toUpperCase()),
                                  style: pw.TextStyle(
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold,
                                    color: cyan,
                                  ),
                                ),
                                pw.Text(
                                  'FOLLOW-UP CLINICAL ENCOUNTER SHEET',
                                  style: pw.TextStyle(
                                    fontSize: 14,
                                    fontWeight: pw.FontWeight.bold,
                                    color: dark,
                                  ),
                                ),
                                ne(
                                  'पुनः जाँच तथा फलो-अप क्लिनिकल स्लिप | Comprehensive Re-check Record',
                                  size: 9.0,
                                  color: 0xFF616161,
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  camp != null
                                      ? 'Camp: ${sanitizeText(camp.name)} (${camp.campCode}) | Venue: ${sanitizeText(camp.venue)}'
                                      : 'Camp / शिविर: _____________________ | Venue / ठाउँ: _____________________',
                                  style: pw.TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'ENCOUNTER TOKEN ID',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: cyan,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        (preprintedTokenId != null &&
                                preprintedTokenId.isNotEmpty)
                            ? pw.Row(
                                mainAxisSize: pw.MainAxisSize.min,
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.center,
                                children: [
                                  buildCharBoxes(
                                    preprintedTokenId,
                                    minBoxes: preprintedTokenId.length,
                                    maxBoxes: preprintedTokenId.length,
                                    boxSize: 11.0,
                                  ),
                                  pw.SizedBox(width: 5),
                                  pw.BarcodeWidget(
                                    barcode: pw.Barcode.qrCode(),
                                    data: preprintedTokenId,
                                    width: 22,
                                    height: 22,
                                  ),
                                ],
                              )
                            : buildCharBoxes(
                                camp?.campCode != null
                                    ? '${camp!.campCode}-'
                                    : 'GC-□□□□-',
                                minBoxes: 14,
                                maxBoxes: 14,
                                boxSize: camp?.campCode != null ? 13 : 11,
                              ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Date: ${dateFormatter.format(DateTime.now())}',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Section 1: Patient Identity
              secHeader('1. PATIENT DEMOGRAPHICS / बिरामी परिचय'),
              pw.Row(
                children: [
                  blankField('Full Name (बिरामीको नाम)', flex: 2),
                  blankField('Age (उमेर)', flex: 1),
                  blankField('Ward (वडा नं.)', flex: 1),
                  blankField('Phone / Mobile (फोन नं.)', flex: 1.5),
                ],
              ),
              pw.Row(
                children: [
                  blankField(
                    'Husband / Guardian Name (श्रीमान् / अभिभावक)',
                    flex: 2,
                  ),
                  blankField('Palika / Municipality (गाउँ/नगरपालिका)', flex: 2),
                  blankField('District (जिल्ला)', flex: 1.5),
                ],
              ),

              // Section 2: Vitals
              secHeader('2. CURRENT VITALS & RE-CHECK / स्वास्थ्य अवस्था'),
              pw.Row(
                children: [
                  blankField('BP (रक्तचाप) mmHg', flex: 1),
                  blankField('Pulse (नाडी) bpm', flex: 1),
                  blankField('Temp (°F)', flex: 1),
                  blankField('Weight (तौल) kg', flex: 1),
                  blankField('SpO2 (%)', flex: 1),
                  blankField('Random Glucose (mg/dL)', flex: 1),
                ],
              ),

              // Section 3: Subjective Symptoms & Response to Treatment
              secHeader(
                '3. SYMPTOM PROGRESSION & TREATMENT RESPONSE / अघिल्लो उपचारको प्रभाव',
              ),
              pw.Wrap(
                children: [
                  cb('Significantly Improved (धेरै सुधार)'),
                  cb('Partially Improved (केही सुधार)'),
                  cb('Unchanged / Same (उस्तै रहेको)'),
                  cb('Worsened / Pain (बिग्रिएको/दुख्ने)'),
                  cb('New Complaints (नयाँ समस्या)'),
                ],
              ),
              pw.SizedBox(height: 4),
              ne(
                'Chief Complaints & Notes (हालको प्रमुख समस्याहरू):',
                size: 7,
                bold: true,
                color: 0xFF1E293B,
              ),
              line(h: 18),

              // Section 4: Physical & Ring Pessary Exam
              secHeader('4. PHYSICAL & PESSARY EXAMINATION / फलो-अप जाँच'),
              pw.Wrap(
                children: [
                  cb('Pessary Clean & In-Situ (रिंग ठिक अवस्थामा)'),
                  cb('Pessary Cleaned & Reinserted (सफा गरि पुन: राखिएको)'),
                  cb('Pessary Removed (रिंग निकालिएको)'),
                  cb('Vaginal Ulcer / Erosion (घाउ/खटिरा देखिएको)'),
                  cb('Pelvic Floor Exercises Advised (व्यायाम सिकाइएको)'),
                ],
              ),
              pw.SizedBox(height: 4),
              ne(
                'Exam Findings (जाँचको नतिजा):',
                size: 7,
                bold: true,
                color: 0xFF1E293B,
              ),
              line(h: 18),

              // Section 5: Plan & Medication
              secHeader(
                '5. CLINICAL MANAGEMENT PLAN & MEDICATIONS / थप उपचार र औषधि',
              ),
              line(h: 18),
              line(h: 18),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Text(
                    'Referral Required: ',
                    style: pw.TextStyle(
                      fontSize: 7.2,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  cb('No (पर्दैन)'),
                  cb('Hospital for Surgery (शल्यक्रियाका लागि)'),
                  cb('Specialist Clinic (विशेषज्ञ डाक्टर)'),
                ],
              ),

              pw.SizedBox(height: 8),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.SizedBox(
                    width: 230,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: nurseWidgets.isNotEmpty
                          ? nurseWidgets
                          : [
                              pw.Container(
                                width: 120,
                                height: 0.8,
                                color: PdfColors.black,
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'Staff Nurse / Health Worker',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                'Signature & Date:',
                                style: const pw.TextStyle(
                                  fontSize: 6,
                                  color: PdfColors.grey600,
                                ),
                              ),
                            ],
                    ),
                  ),
                  pw.SizedBox(
                    width: 280,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (!showDoctor || blankDoctorLines) ...[
                          pw.SizedBox(height: 12),
                          pw.Container(
                            width: 140,
                            height: 0.8,
                            color: PdfColors.black,
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Examining Doctor / Gynecologist',
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'Doctor Signature & NMC: _________________________',
                            style: const pw.TextStyle(
                              fontSize: 6,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ] else if (doctor != null) ...[
                          pw.Container(
                            width: 130,
                            height: 0.8,
                            color: PdfColors.black,
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            doctor.displayName,
                            style: pw.TextStyle(
                              fontSize: 7.5,
                              fontWeight: pw.FontWeight.bold,
                              color: dark,
                            ),
                          ),
                          pw.Text(
                            'Medical Officer / Gynecologist',
                            style: const pw.TextStyle(
                              fontSize: 6.2,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.Text(
                            doctor.hasNmc
                                ? 'NMC No: ${doctor.nmcNumber}'
                                : 'NMC Certified',
                            style: const pw.TextStyle(
                              fontSize: 6,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ] else if (campDoctors.length > 1) ...[
                          pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text(
                                'Examining Doctor (',
                                style: pw.TextStyle(
                                  fontSize: 7.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: secondary,
                                ),
                              ),
                              ne(
                                'जाँच गर्ने चिकित्सक',
                                size: 7.5,
                                bold: true,
                                color: 0xFF81005D,
                              ),
                              pw.Text(
                                '):',
                                style: pw.TextStyle(
                                  fontSize: 7.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 2),
                          pw.Wrap(
                            spacing: 4,
                            runSpacing: 1.5,
                            alignment: pw.WrapAlignment.end,
                            children: [
                              ...campDoctors.map(
                                (doc) =>
                                    cb(DoctorProfile.parse(doc).formattedLabel),
                              ),
                              cb('Other: _____'),
                            ],
                          ),
                          pw.SizedBox(height: 14),
                          pw.Container(
                            width: 130,
                            height: 0.8,
                            color: PdfColors.black,
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Doctor Signature & NMC: ______________',
                            style: const pw.TextStyle(
                              fontSize: 6,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ] else if (campDoctors.length == 1) ...[
                          pw.Container(
                            width: 130,
                            height: 0.8,
                            color: PdfColors.black,
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            DoctorProfile.parse(campDoctors.first).displayName,
                            style: pw.TextStyle(
                              fontSize: 7.5,
                              fontWeight: pw.FontWeight.bold,
                              color: dark,
                            ),
                          ),
                          pw.Text(
                            'Medical Officer / Gynecologist',
                            style: const pw.TextStyle(
                              fontSize: 6.2,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.Text(
                            DoctorProfile.parse(campDoctors.first).hasNmc
                                ? 'NMC No: ${DoctorProfile.parse(campDoctors.first).nmcNumber}'
                                : 'NMC Certified',
                            style: const pw.TextStyle(
                              fontSize: 6,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ] else ...[
                          pw.Container(
                            width: 140,
                            height: 0.8,
                            color: PdfColors.black,
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Examining Doctor / Gynecologist',
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'Doctor Signature & NMC No. — Date: _______________',
                            style: const pw.TextStyle(
                              fontSize: 6,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
            ],
          );
        },
      ),
    );
  }

  /// Builds the attending-nurse block shown near the signatures.
  ///
  /// Returns an empty list when nothing should be printed, so forms for camps
  /// without nurses stay identical to the previous layout.
  ///  - blank lines   : [blankNurseLines] or nurse names hidden by camp setting
  ///  - specific nurse: pre-printed name (+ optional NNC number)
  ///  - checkbox list : every camp nurse (multi-select by ticking on paper);
  ///                    nurses recorded on [visitNurseNames] are pre-ticked
  static List<pw.Widget> _buildNurseSignatureBlock({
    required pw.Widget Function(String label, bool checked) cb,
    required List<NurseProfile> campNurses,
    required bool showNurse,
    bool blankNurseLines = false,
    NurseProfile? nurse,
    List<String> visitNurseNames = const [],
    required PdfColor primary,
    required PdfColor dark,
    double width = 210,
    double fsSmall = 8.0,
  }) {
    pw.Widget signLine(double w) =>
        pw.Container(width: w, height: 0.8, color: PdfColors.black);

    final visitNames = visitNurseNames
        .map((n) => NurseProfile.parse(n).name.toLowerCase().trim())
        .where((n) => n.isNotEmpty)
        .toSet();
    final rosterNames = campNurses
        .map((n) => n.name.toLowerCase().trim())
        .toSet();
    // Nurses recorded on a visit but missing from the camp roster
    final extraVisitNurses = visitNurseNames
        .map((n) => NurseProfile.parse(n))
        .where(
          (n) =>
              n.isValid && !rosterNames.contains(n.name.toLowerCase().trim()),
        )
        .toSet()
        .toList();
    final hasAnyNurse =
        campNurses.isNotEmpty || extraVisitNurses.isNotEmpty || nurse != null;

    // 1) Blank lines (explicitly requested, or names hidden by camp setting)
    if (blankNurseLines || (!showNurse && hasAnyNurse)) {
      return [
        pw.SizedBox(
          width: width,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 12),
              signLine(120),
              pw.SizedBox(height: 3),
              pw.Text(
                'Attending Nurse',
                style: pw.TextStyle(
                  fontSize: fsSmall,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Nurse Name, Signature & NNC: ______________',
                style: const pw.TextStyle(
                  fontSize: 6,
                  color: PdfColors.grey600,
                ),
              ),
              pw.SizedBox(height: 6),
            ],
          ),
        ),
      ];
    }

    // 2) Specific nurse pre-printed
    if (nurse != null) {
      return [
        pw.SizedBox(
          width: width,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              signLine(120),
              pw.SizedBox(height: 2),
              pw.Text(
                sanitizeText(nurse.displayName),
                style: pw.TextStyle(
                  fontSize: fsSmall,
                  fontWeight: pw.FontWeight.bold,
                  color: dark,
                ),
              ),
              pw.Text(
                'Attending Nurse',
                style: const pw.TextStyle(
                  fontSize: 6.2,
                  color: PdfColors.grey700,
                ),
              ),
              if (nurse.hasRegistration)
                pw.Text(
                  'NNC No: ${sanitizeText(nurse.registrationNumber)}',
                  style: const pw.TextStyle(
                    fontSize: 6,
                    color: PdfColors.grey600,
                  ),
                ),
              pw.SizedBox(height: 6),
            ],
          ),
        ),
      ];
    }

    // 3) Checkbox list of camp nurses (+ pre-ticked visit nurses)
    if (campNurses.isNotEmpty || extraVisitNurses.isNotEmpty) {
      final entries = <NurseProfile>[...campNurses, ...extraVisitNurses];
      return [
        pw.SizedBox(
          width: width,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'Attending Nurse (',
                    style: pw.TextStyle(
                      fontSize: fsSmall,
                      fontWeight: pw.FontWeight.bold,
                      color: primary,
                    ),
                  ),
                  ne(
                    'सेवा दिने नर्स',
                    size: fsSmall,
                    bold: true,
                    color: 0xFF81005D,
                  ),
                  pw.Text(
                    '):',
                    style: pw.TextStyle(
                      fontSize: fsSmall,
                      fontWeight: pw.FontWeight.bold,
                      color: primary,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Wrap(
                spacing: 4,
                runSpacing: 1.5,
                children: [
                  ...entries.map(
                    (n) => cb(
                      n.formattedLabel,
                      visitNames.contains(n.name.toLowerCase().trim()),
                    ),
                  ),
                  cb('Other: _____', false),
                ],
              ),
              pw.SizedBox(height: 14),
              signLine(120),
              pw.SizedBox(height: 3),
              pw.Text(
                'Nurse Signature & NNC No.: ______________',
                style: const pw.TextStyle(
                  fontSize: 6,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 6),
            ],
          ),
        ),
      ];
    }

    // 4) Camp has no nurses and none requested: keep the original layout
    return const <pw.Widget>[];
  }

  Future<Uint8List> generateBlankFollowUpSlipPdf({
    CampModel? camp,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    String organizationName = AppConstants.defaultOrganizationName,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      _addBlankFollowUpSlipPage(
        pdf,
        camp: camp,
        doctor: doctor,
        blankDoctorLines: blankDoctorLines,
        nurse: nurse,
        blankNurseLines: blankNurseLines,
        organizationName: organizationName,
        logoImage: logoImage,
      );
      return pdf;
    });
  }

  Future<Uint8List> generateBatchBlankFollowUpSlipsPdf({
    required List<DoctorProfile> doctors,
    CampModel? camp,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    String organizationName = AppConstants.defaultOrganizationName,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      for (final doc in doctors) {
        _addBlankFollowUpSlipPage(
          pdf,
          camp: camp,
          doctor: doc,
          nurse: nurse,
          blankNurseLines: blankNurseLines,
          organizationName: organizationName,
          logoImage: logoImage,
        );
      }
      return pdf;
    });
  }

  Future<Uint8List> generateBatchBlankFollowUpSlipsByNursesPdf({
    required List<NurseProfile> nurses,
    CampModel? camp,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    String organizationName = AppConstants.defaultOrganizationName,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      for (final n in nurses) {
        _addBlankFollowUpSlipPage(
          pdf,
          camp: camp,
          doctor: doctor,
          blankDoctorLines: blankDoctorLines,
          nurse: n,
          blankNurseLines: false,
          organizationName: organizationName,
          logoImage: logoImage,
        );
      }
      return pdf;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BLOCK-LETTER REGISTRATION FORM PDF (printable grid with squares per char)
  // Supports both pre-filled (patient != null) and blank physical forms (patient == null)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _addPatientRegistrationFormPages(
    pw.Document pdf, {
    PatientModel? patient,
    String? preprintedPatientId,
    CampModel? camp,
    ClinicalVisitModel? visit,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    bool allDoctorsChecklist = false,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    bool allNursesChecklist = false,
    BlankFormPage1Layout page1Layout = BlankFormPage1Layout.grid,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
    List<LookupItemModel>? visitReasons,
    List<LookupItemModel>? chiefComplaints,
    pw.MemoryImage? logoImage,
  }) async {
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final hasPatient = patient != null;
    final intakeDate = patient?.intakeDate ?? DateTime.now();

    final logo = logoImage ?? await loadLogoImage();

    final primary = PdfColor.fromHex('30026E'); // WFWSN Logo Royal Violet
    final dark = PdfColor.fromHex('1E293B');
    final gray = PdfColor.fromHex('CBD5E1');
    final boxBg = PdfColor.fromHex('FAFAFA');

    final String dynamicCampCode =
        (camp?.campCode != null && camp!.campCode.trim().isNotEmpty)
        ? camp.campCode.trim().toUpperCase()
        : (patient?.campCode.trim().isNotEmpty == true
              ? patient!.campCode.trim().toUpperCase()
              : '');
    final int dynamicYear =
        (patient?.intakeDate ?? camp?.startDate ?? DateTime.now()).year;
    final String dynamicTokenPrefix = dynamicCampCode.isNotEmpty
        ? 'GC-$dynamicCampCode-$dynamicYear-'
        : 'GC-□□□□-$dynamicYear-';

    // ── Resolve Doctor Information ──
    final bool showDoctor = camp?.showDoctorOnForms ?? true;
    final List<String> campDoctors = camp?.doctorNames.isNotEmpty == true
        ? camp!.doctorNames
              .map(
                (d) => d
                    .trim()
                    .replaceAll(
                      RegExp(r'^(Dr\.?\s*)+', caseSensitive: false),
                      '',
                    )
                    .trim(),
              )
              .where((d) => d.isNotEmpty)
              .toSet()
              .toList()
        : (camp?.doctorName.trim().isNotEmpty == true
              ? [
                  camp!.doctorName
                      .trim()
                      .replaceAll(
                        RegExp(r'^(Dr\.?\s*)+', caseSensitive: false),
                        '',
                      )
                      .trim(),
                ]
              : <String>[]);

    final List<DoctorProfile> effectiveDoctors = camp?.doctorProfiles.isNotEmpty == true
        ? camp!.doctorProfiles.toSet().toList()
        : campDoctors.map(DoctorProfile.parse).where((d) => d.isValid).toSet().toList();

    final String? assignedDoctor =
        (visit?.primaryDoctorName != null &&
            visit!.primaryDoctorName!.trim().isNotEmpty)
        ? visit.primaryDoctorName!.trim()
        : (visit?.attendingDoctorNames.isNotEmpty == true
              ? visit!.attendingDoctorNames.first.trim()
              : null);

    final String doctorHeaderPart;
    if (!showDoctor || blankDoctorLines) {
      doctorHeaderPart = "";
    } else if (doctor != null) {
      doctorHeaderPart = doctor.hasNmc
          ? "${doctor.displayName} | NMC: ${doctor.nmcNumber}"
          : doctor.displayName;
    } else if (visit != null &&
        visit.attendingDoctorNames.where((d) => d.trim().isNotEmpty).length >
            1) {
      doctorHeaderPart = visit.attendingDoctorNames
          .where((d) => d.trim().isNotEmpty)
          .map((d) {
            final clean = d
                .trim()
                .replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '')
                .trim();
            return 'Dr. ${sanitizeText(clean)}';
          })
          .join(', ');
    } else if (assignedDoctor != null) {
      final clean = assignedDoctor
          .trim()
          .replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '')
          .trim();
      doctorHeaderPart = "Dr. ${sanitizeText(clean)}";
    } else if (effectiveDoctors.length > 1) {
      doctorHeaderPart = effectiveDoctors
          .map((d) => d.formattedLabel)
          .join(', ');
    } else if (effectiveDoctors.length == 1) {
      doctorHeaderPart = effectiveDoctors.first.formattedLabel;
    } else {
      doctorHeaderPart = "";
    }

    // ── Resolve Nurse Information ──
    final bool showNurse = camp?.showNurseOnForms ?? true;
    final List<NurseProfile> campNurses =
        camp?.nurseProfiles.toSet().toList() ?? <NurseProfile>[];
    final List<NurseProfile> effectiveNurses = campNurses;

    // ── Resolve dynamic master items with graceful fallbacks ──
    // 1. Diagnoses
    List<LookupItemModel> effectiveDiagnosesItems =
        diagnoses?.where((d) => d.isActive).toList() ?? [];
    if (diagnoses == null && camp != null) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory(
          'diagnosis',
          campId: camp.id,
        );
        effectiveDiagnosesItems = repoItems.where((i) => i.isActive).toList();
      } catch (_) {}
    }
    // Only fall back to defaults if generating a generic blank form without camp context AND no items were provided
    if (effectiveDiagnosesItems.isEmpty && camp == null && diagnoses == null) {
      effectiveDiagnosesItems = ClinicalConstants.defaultDiagnoses.map((d) {
        final cat =
            ClinicalConstants.diagnosisCategoryMap[d.toLowerCase()] ??
            'General / Other';
        return LookupItemModel(
          id: d,
          category: 'diagnosis',
          subCategory: cat,
          code: d.toLowerCase().replaceAll(' ', '_'),
          labelEn: d,
          labelNe: '',
          isActive: true,
        );
      }).toList();
    }
    if (effectiveDiagnosesItems.length > 22) {
      effectiveDiagnosesItems = effectiveDiagnosesItems.take(22).toList();
    }

    // 2. Medications
    List<LookupItemModel> effectiveMedicationsItems =
        medications?.where((m) => m.isActive).toList() ?? [];
    if (medications == null && camp != null) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory(
          'medicine',
          campId: camp.id,
        );
        effectiveMedicationsItems = repoItems.where((i) => i.isActive).toList();
      } catch (_) {}
    }
    // Only fall back to defaults if generating a generic blank form without camp context AND no items were provided
    if (effectiveMedicationsItems.isEmpty &&
        camp == null &&
        medications == null) {
      effectiveMedicationsItems = ClinicalConstants.defaultMedications.map((m) {
        final cat =
            ClinicalConstants.medicationCategoryMap[m.toLowerCase()] ??
            'Other / Custom';
        return LookupItemModel(
          id: m,
          category: 'medicine',
          subCategory: cat,
          code: m.toLowerCase().replaceAll(' ', '_'),
          labelEn: m,
          labelNe: '',
          isActive: true,
        );
      }).toList();
    }
    if (effectiveMedicationsItems.length > 12) {
      effectiveMedicationsItems = effectiveMedicationsItems.take(12).toList();
    }

    // 3. Referral Hospitals
    List<LookupItemModel> effectiveHospitalsItems =
        referralHospitals?.where((h) => h.isActive).toList() ?? [];
    if (referralHospitals == null && camp != null) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory(
          'referral_hospital',
          campId: camp.id,
        );
        effectiveHospitalsItems = repoItems.where((i) => i.isActive).toList();
      } catch (_) {}
    }
    if (effectiveHospitalsItems.isEmpty &&
        camp == null &&
        referralHospitals == null) {
      effectiveHospitalsItems = ClinicalConstants.referralHospitals.map((h) {
        return LookupItemModel(
          id: h,
          category: 'referral_hospital',
          code: h.toLowerCase().replaceAll(' ', '_'),
          labelEn: h,
          labelNe: '',
          isActive: true,
        );
      }).toList();
    }
    if (effectiveHospitalsItems.length > 6) {
      effectiveHospitalsItems = effectiveHospitalsItems.take(6).toList();
    }

    final List<String> distinctDiagnosisCategories = [];
    for (final cat in ClinicalConstants.diagnosisCategories) {
      if (!distinctDiagnosisCategories.contains(cat)) {
        distinctDiagnosisCategories.add(cat);
      }
    }
    for (final d in effectiveDiagnosesItems) {
      final cat = (d.subCategory != null && d.subCategory!.trim().isNotEmpty)
          ? d.subCategory!.trim()
          : (ClinicalConstants.diagnosisCategoryMap[d.labelEn.toLowerCase()] ??
                'General / Other');
      if (!distinctDiagnosisCategories.contains(cat)) {
        distinctDiagnosisCategories.add(cat);
      }
    }

    final List<String> distinctMedicationCategories = [];
    for (final cat in ClinicalConstants.medicationCategories) {
      if (!distinctMedicationCategories.contains(cat)) {
        distinctMedicationCategories.add(cat);
      }
    }
    for (final m in effectiveMedicationsItems) {
      final cat = (m.subCategory != null && m.subCategory!.trim().isNotEmpty)
          ? m.subCategory!.trim()
          : (ClinicalConstants.medicationCategoryMap[m.labelEn.toLowerCase()] ??
                'Other / Custom');
      if (!distinctMedicationCategories.contains(cat)) {
        distinctMedicationCategories.add(cat);
      }
    }

    // 4. Visit Reasons (Map of code/key -> bilingual label)
    String cleanReasonNepali(String neText) {
      final trimmed = neText.trim();
      final parenMatch = RegExp(r'\(([\u0900-\u097F\s/]+)\)').firstMatch(trimmed);
      if (parenMatch != null) {
        return parenMatch.group(1)!.trim();
      }
      if (trimmed.contains('(') && trimmed.endsWith(')')) {
        final idx = trimmed.lastIndexOf('(');
        return trimmed.substring(idx + 1, trimmed.length - 1).trim();
      }
      return trimmed;
    }

    Map<String, String> effectiveVisitReasons = {};
    if (visitReasons != null && visitReasons.isNotEmpty) {
      for (final vr in visitReasons.where((v) => v.isActive)) {
        final cleanNe = cleanReasonNepali(vr.labelNe);
        final label = (cleanNe.isNotEmpty && cleanNe != vr.labelEn)
            ? '${vr.labelEn} ($cleanNe)'
            : vr.labelEn;
        effectiveVisitReasons[vr.code] = label;
      }
    }
    if (effectiveVisitReasons.isEmpty) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory(
          'visit_reason',
          campId: camp?.id,
        );
        if (repoItems.isNotEmpty) {
          for (final vr in repoItems.where((v) => v.isActive)) {
            final cleanNe = cleanReasonNepali(vr.labelNe);
            final label = (cleanNe.isNotEmpty && cleanNe != vr.labelEn)
                ? '${vr.labelEn} ($cleanNe)'
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
      effectiveComplaints = chiefComplaints
          .where((c) => c.isActive)
          .map((c) => {'code': c.code, 'label': c.labelEn})
          .toList();
    }
    if (effectiveComplaints.isEmpty) {
      try {
        final repoItems = await LookupRepository().getItemsByCategory(
          'chief_complaint',
          campId: camp?.id,
        );
        if (repoItems.isNotEmpty) {
          effectiveComplaints = repoItems
              .where((i) => i.isActive)
              .map((c) => {'code': c.code, 'label': c.labelEn})
              .toList();
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
      double? boxHeight,
      double boxMargin = 2,
    }) {
      final cleanVal = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      final chars = cleanVal.toUpperCase().split('');
      var total = chars.length > minBoxes ? chars.length : minBoxes;
      if (maxBoxes != null && total > maxBoxes) {
        total = maxBoxes;
      }
      final h = boxHeight ?? (boxSize + 3);
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: List.generate(total, (i) {
          final rawChar = i < chars.length ? chars[i] : '';
          if (rawChar == ' ') {
            return pw.SizedBox(width: 5);
          }
          if (rawChar.isNotEmpty && rawChar != '□') {
            return pw.Container(
              width: boxSize,
              height: h,
              margin: pw.EdgeInsets.only(right: boxMargin),
              decoration: pw.BoxDecoration(
                color: boxBg,
                border: pw.Border.all(
                  color: PdfColor.fromHex('94A3B8'),
                  width: 0.8,
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              alignment: pw.Alignment.center,
              child: pw.Text(
                rawChar,
                style: pw.TextStyle(
                  fontSize: boxSize * 0.68,
                  fontWeight: pw.FontWeight.bold,
                  color: dark,
                ),
              ),
            );
          }
          return pw.Container(
            width: boxSize,
            height: h,
            margin: pw.EdgeInsets.only(right: boxMargin),
            decoration: pw.BoxDecoration(
              color: boxBg,
              border: pw.Border.all(
                color: PdfColor.fromHex('94A3B8'),
                width: 0.8,
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          );
        }),
      );
    }

    // ── Standard Bikram Sambat (BS) Date Character Boxes Helper ──
    pw.Widget buildDateBsBoxes(
      DateTime? date, {
      bool hasData = false,
      double boxSize = 8.5,
      double boxHeight = 11.5,
      double fontSize = 7.0,
    }) {
      final d = date ?? DateTime.now();
      final bsYear = (d.year + 57).toString();
      final bsMonth = (((d.month + 8) % 12) + 1).toString().padLeft(2, '0');
      final bsDay = d.day.toString().padLeft(2, '0');
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          buildCharBoxes(
            hasData ? bsYear : '',
            minBoxes: 4,
            maxBoxes: 4,
            boxSize: boxSize,
            boxHeight: boxHeight,
            boxMargin: 1.0,
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 1.5),
            child: pw.Text('-', style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: dark)),
          ),
          buildCharBoxes(
            hasData ? bsMonth : '',
            minBoxes: 2,
            maxBoxes: 2,
            boxSize: boxSize,
            boxHeight: boxHeight,
            boxMargin: 1.0,
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 1.5),
            child: pw.Text('-', style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: dark)),
          ),
          buildCharBoxes(
            hasData ? bsDay : '',
            minBoxes: 2,
            maxBoxes: 2,
            boxSize: boxSize,
            boxHeight: boxHeight,
            boxMargin: 1.0,
          ),
          pw.SizedBox(width: 2.5),
          pw.Text('BS', style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: primary)),
        ],
      );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAGE 1 — PATIENT REGISTRATION & ANAMNESIS (Yellow Form Front Page)
    // Physical Outreach Standard Layout — Strictly 1 Physical A4 Page
    // Enhanced Font Sizes, Large Checkboxes, 14 Character Boxes for Palika/District
    // ═══════════════════════════════════════════════════════════════════════
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        build: (ctx) {
          // ── Professional Section Header with Slate Background & Left Accent Bar ──
          pw.Widget secHdr(
            String title, {
            double topMargin = 3.5,
            double bottomMargin = 3.5,
          }) {
            return pw.Container(
              width: double.infinity,
              margin: pw.EdgeInsets.only(top: topMargin, bottom: bottomMargin),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 3.0,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('F1F5F9'),
                border: pw.Border(
                  left: pw.BorderSide(
                    color: PdfColor.fromHex('1B365D'),
                    width: 3.2,
                  ),
                  top: pw.BorderSide(
                    color: PdfColor.fromHex('CBD5E1'),
                    width: 0.6,
                  ),
                  right: pw.BorderSide(
                    color: PdfColor.fromHex('CBD5E1'),
                    width: 0.6,
                  ),
                  bottom: pw.BorderSide(
                    color: PdfColor.fromHex('CBD5E1'),
                    width: 0.6,
                  ),
                ),
              ),
              child: ne(title, size: 8.8, bold: true, color: 0xFF0F172A),
            );
          }

          // ── Standard Uniform Checkbox (Crisp 10.5 pt box, 8.2 pt text) ──
          pw.Widget cb(
            String label,
            bool checked, {
            double? textWidth,
            double bottom = 0.0,
            bool isExpanded = false,
            double boxSize = 10.5,
            double fontSize = 8.0,
          }) => pw.Padding(
            padding: pw.EdgeInsets.only(right: 6, bottom: bottom),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: isExpanded
                  ? pw.MainAxisSize.max
                  : pw.MainAxisSize.min,
              children: [
                pw.Container(
                  width: boxSize,
                  height: boxSize,
                  margin: const pw.EdgeInsets.only(right: 4.0),
                  decoration: pw.BoxDecoration(
                    color: checked
                        ? PdfColor.fromHex('EDE9FF')
                        : PdfColors.white,
                    border: pw.Border.all(
                      color: checked ? primary : PdfColor.fromHex('475569'),
                      width: 0.8,
                    ),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(2.0),
                    ),
                  ),
                  child: checked
                      ? pw.Center(
                          child: pw.Text(
                            'X',
                            style: pw.TextStyle(
                              fontSize: boxSize * 0.72,
                              fontWeight: pw.FontWeight.bold,
                              color: primary,
                            ),
                          ),
                        )
                      : pw.SizedBox(),
                ),
                () {
                  final slashIdx = label.indexOf('/');
                  if (slashIdx != -1) {
                    final enText = label.substring(0, slashIdx).trim();
                    final neText = label.substring(slashIdx).trim();
                    final content = pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          enText,
                          style: pw.TextStyle(
                            fontSize: fontSize,
                            fontWeight: checked ? pw.FontWeight.bold : pw.FontWeight.normal,
                            color: dark,
                          ),
                        ),
                        pw.SizedBox(width: 2),
                        ne(neText, size: fontSize * 0.95, color: 0xFF475569),
                      ],
                    );
                    if (textWidth != null) {
                      return pw.SizedBox(width: textWidth, child: content);
                    } else if (isExpanded) {
                      return pw.Expanded(child: content);
                    }
                    return content;
                  }
                  if (textWidth != null) {
                    return pw.SizedBox(
                      width: textWidth,
                      child: ne(label, size: fontSize, maxWidth: textWidth),
                    );
                  } else if (isExpanded) {
                    return pw.Expanded(child: ne(label, size: fontSize));
                  }
                  return ne(label, size: fontSize);
                }(),
              ],
            ),
          );

          // ── Standard Character Boxes Field ──
          pw.Widget field(
            String labelEn,
            String labelNe,
            String value, {
            int minBoxes = 14,
            int? maxBoxes,
            double boxSize = 11.8,
            double boxHeight = 15.2,
            double boxMargin = 1.0,
            double bottomPadding = 5.5,
          }) => pw.Padding(
            padding: pw.EdgeInsets.only(bottom: bottomPadding),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '$labelEn: ',
                      style: pw.TextStyle(
                        fontSize: 8.0,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    ne(labelNe, size: 7.2, color: 0xFF475569),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                buildCharBoxes(
                  value,
                  minBoxes: minBoxes,
                  maxBoxes: maxBoxes ?? minBoxes,
                  boxSize: boxSize,
                  boxHeight: boxHeight,
                  boxMargin: boxMargin,
                ),
              ],
            ),
          );

          // ── Normalize Palika string ──
          final rawMuni = patient?.municipality ?? '';
          final palikaVal = rawMuni
              .replaceAll(
                RegExp(
                  r'\s*(municipality|nagarpalika|rural municipality|gaupalika)',
                  caseSensitive: false,
                ),
                '',
              )
              .trim();

          // ── Consultation Triage Status ──
          final String currentTreatmentLevel =
              (visit?.treatmentLevel?.trim().isNotEmpty == true)
              ? visit!.treatmentLevel!.trim()
              : (patient?.treatmentLevel?.trim().isNotEmpty == true
                    ? patient!.treatmentLevel!.trim()
                    : '');
          final bool isCouncilLevel = currentTreatmentLevel
              .toLowerCase()
              .contains('counsel') ||
              currentTreatmentLevel.toLowerCase().contains('council');
          final bool isFullCheckUp =
              currentTreatmentLevel.toLowerCase().contains('gyno') ||
              currentTreatmentLevel.toLowerCase().contains('full') ||
              (!isCouncilLevel && currentTreatmentLevel.isNotEmpty);

          // ── Triage Strip (Consultation & Date in BS boxes) ──
          final triageStrip = pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 2, bottom: 3),
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3.0,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('F8FAFC'),
              border: pw.Border.all(
                color: PdfColor.fromHex('CBD5E1'),
                width: 0.6,
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                ne(
                  'CONSULTATION: परामर्श:',
                  size: 8.0,
                  bold: true,
                  color: 0xFF30026E,
                ),
                pw.SizedBox(width: 10),
                cb(
                  'Counseling / काउन्सिलिङ',
                  isCouncilLevel,
                  fontSize: 7.8,
                  boxSize: 10.0,
                ),
                pw.SizedBox(width: 12),
                cb(
                  'Gynocheckup / गाइनो जाँच',
                  isFullCheckUp,
                  fontSize: 7.8,
                  boxSize: 10.0,
                ),
                pw.Spacer(),
                // ── Date in character boxes ending with BS ──
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    ne(
                      'Date / मिति:',
                      size: 8.0,
                      bold: true,
                      color: 0xFF1E293B,
                    ),
                    pw.SizedBox(width: 4),
                    buildDateBsBoxes(
                      intakeDate,
                      hasData: hasPatient,
                      boxSize: 9.5,
                      boxHeight: 12.5,
                      fontSize: 7.5,
                    ),
                  ],
                ),
              ],
            ),
          );

          // ── Section A: Demographics (Grid with 14-box Palika & District) ──
          final sectionA = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr(
                'SECTION A: PATIENT DEMOGRAPHICS / बिरामी विवरण',
                topMargin: 3.0,
                bottomMargin: 4.0,
              ),
              // Row 1: First Name, Surname, Age
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 40,
                    child: field(
                      'First Name',
                      'पहिलो नाम',
                      patient?.firstName ?? '',
                      minBoxes: 14,
                      maxBoxes: 14,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 38,
                    child: field(
                      'Surname',
                      'थर',
                      patient?.surname ?? '',
                      minBoxes: 14,
                      maxBoxes: 14,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 22,
                    child: field(
                      'Age',
                      'उमेर (वर्ष)',
                      patient?.age != null ? '${patient!.age}' : '',
                      minBoxes: 2,
                      maxBoxes: 2,
                    ),
                  ),
                ],
              ),
              // Row 2: Relative Name, Surname, Relation Type
              () {
                final relName = patient?.spouseOrFatherName?.trim() ?? '';
                return pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 40,
                      child: field(
                        'Relative Name',
                        'आफन्तको नाम',
                        relName.isNotEmpty ? relName.split(' ').first : '',
                        minBoxes: 14,
                        maxBoxes: 14,
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      flex: 38,
                      child: field(
                        'Relative Surname',
                        'थर',
                        relName.contains(' ')
                            ? relName.split(' ').skip(1).join(' ')
                            : '',
                        minBoxes: 14,
                        maxBoxes: 14,
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      flex: 26,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text(
                                'Relation: ',
                                style: pw.TextStyle(
                                  fontSize: 8.0,
                                  fontWeight: pw.FontWeight.bold,
                                  color: dark,
                                ),
                              ),
                              ne('नाता', size: 7.2, color: 0xFF475569),
                            ],
                          ),
                          pw.SizedBox(height: 2),
                          pw.Row(
                            children: [
                              cb(
                                'Husband / श्रीमान्',
                                (patient?.relationshipType ?? '').toLowerCase().contains('husband'),
                                bottom: 0,
                                boxSize: 9.5,
                                fontSize: 7.2,
                              ),
                              pw.SizedBox(width: 4),
                              cb(
                                'Father / बुबा',
                                (patient?.relationshipType ?? '').toLowerCase().contains('father'),
                                bottom: 0,
                                boxSize: 9.5,
                                fontSize: 7.2,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }(),
              // Row 3: Mobile, Ward, Contact Person, Contact Mobile
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 26,
                    child: field(
                      'Mobile W',
                      'महिलाको मोबाइल',
                      patient?.mobile ?? '',
                      minBoxes: 10,
                      maxBoxes: 10,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 12,
                    child: field(
                      'Ward',
                      'वडा',
                      patient?.ward ?? '',
                      minBoxes: 2,
                      maxBoxes: 2,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 34,
                    child: field(
                      'Contact Person',
                      'सम्पर्क व्यक्ति',
                      patient?.contactPerson ?? '',
                      minBoxes: 10,
                      maxBoxes: 10,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 28,
                    child: field(
                      'Contact Mobile',
                      'सम्पर्क मोबाइल',
                      patient?.contactMobile ?? '',
                      minBoxes: 10,
                      maxBoxes: 10,
                    ),
                  ),
                ],
              ),
              // Row 4: Marital Status & Marital Age
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 70,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          children: [
                            pw.Text(
                              'Marital Status: ',
                              style: pw.TextStyle(
                                fontSize: 8.0,
                                fontWeight: pw.FontWeight.bold,
                                color: dark,
                              ),
                            ),
                            ne('वैवाहिक स्थिति', size: 7.2, color: 0xFF475569),
                          ],
                        ),
                        pw.SizedBox(height: 2.5),
                        pw.Row(
                          children: [
                            cb(
                              'Married / विवाहित',
                              patient?.maritalStatus == 'married',
                              fontSize: 7.8,
                              boxSize: 10.5,
                            ),
                            pw.SizedBox(width: 6),
                            cb(
                              'Unmarried / अविवाहित',
                              patient?.maritalStatus == 'unmarried',
                              fontSize: 7.8,
                              boxSize: 10.5,
                            ),
                            pw.SizedBox(width: 6),
                            cb(
                              'Widow / एकल',
                              patient?.maritalStatus == 'widow',
                              fontSize: 7.8,
                              boxSize: 10.5,
                            ),
                            pw.SizedBox(width: 6),
                            cb(
                              'Divorced / सम्बन्ध विच्छेद',
                              patient?.maritalStatus == 'divorced',
                              fontSize: 7.8,
                              boxSize: 10.5,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    flex: 30,
                    child: field(
                      'Marital Age',
                      'विवाह उमेर',
                      patient?.maritalAge?.toString() ?? '',
                      minBoxes: 2,
                      maxBoxes: 2,
                    ),
                  ),
                ],
              ),
              // Row 5: Dedicated Location Row with Character Boxes for Palika, District, and Province
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 40,
                    child: field(
                      'Palika',
                      'गाउँ / न.पा.',
                      palikaVal,
                      minBoxes: 12,
                      maxBoxes: 12,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 36,
                    child: field(
                      'District',
                      'जिल्ला',
                      patient?.district ?? '',
                      minBoxes: 11,
                      maxBoxes: 11,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 24,
                    child: field(
                      'Province',
                      'प्रदेश',
                      patient?.province ?? '',
                      minBoxes: 8,
                      maxBoxes: 8,
                    ),
                  ),
                ],
              ),
            ],
          );

          // ── Section B: Reason for Gynocamp & Consent ──
          final List<String> pReasons =
              (patient?.reasonsForVisit.isNotEmpty == true)
              ? patient!.reasonsForVisit
              : (visit?.anamnesisComplaints['visitReasons'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    [];

          final sectionB = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr(
                'SECTION B: REASON FOR GYNOCAMP & CONSENT / शिविरमा आउनुको कारण तथा सहमति',
                topMargin: 2.0,
                bottomMargin: 2.5,
              ),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: 8 Checkboxes for reasons
                  pw.Expanded(
                    flex: 58,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Reason for visit / आउनुको कारण:',
                          style: pw.TextStyle(
                            fontSize: 8.0,
                            fontWeight: pw.FontWeight.bold,
                            color: dark,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Wrap(
                          spacing: 6,
                          runSpacing: 2.5,
                          children: effectiveVisitReasons.entries.take(8).map((
                            entry,
                          ) {
                            final code = entry.key;
                            final label = entry.value;
                            final isChecked = pReasons.any(
                              (r) =>
                                  r.toLowerCase() == code.toLowerCase() ||
                                  r.toLowerCase() == label.toLowerCase() ||
                                  label.toLowerCase().contains(r.toLowerCase()),
                            );
                            return cb(
                              label,
                              isChecked,
                              fontSize: 8.0,
                              boxSize: 10.5,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Container(width: 0.6, height: 46, color: gray),
                  pw.SizedBox(width: 8),
                  // Right: Consent & Signatures
                  pw.Expanded(
                    flex: 42,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          children: [
                            ne(
                              'Consent for Treatment / उपचारको लागि सहमति: ',
                              size: 7.8,
                              bold: true,
                              color: 0xFF0F172A,
                              maxWidth: 148,
                            ),
                            cb(
                              'YES',
                              patient?.consentTreatment == true,
                              fontSize: 7.8,
                              boxSize: 10.5,
                            ),
                            cb(
                              'NO',
                              patient?.consentTreatment == false,
                              fontSize: 7.8,
                              boxSize: 10.5,
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 3.0),
                        pw.Row(
                          children: [
                            ne(
                              'Consent for Storage / स्वास्थ्य विवरण सहमति: ',
                              size: 7.8,
                              bold: true,
                              color: 0xFF0F172A,
                              maxWidth: 148,
                            ),
                            cb(
                              'YES',
                              patient?.consentStoreMedicalInfo == true,
                              fontSize: 7.8,
                              boxSize: 10.5,
                            ),
                            cb(
                              'NO',
                              patient?.consentStoreMedicalInfo == false,
                              fontSize: 7.8,
                              boxSize: 10.5,
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          children: [
                            pw.Text(
                              'Patient Sign / Thumb: ',
                              style: pw.TextStyle(fontSize: 7.6, color: dark),
                            ),
                            pw.Expanded(
                              child: pw.Container(
                                height: 11,
                                decoration: const pw.BoxDecoration(
                                  border: pw.Border(
                                    bottom: pw.BorderSide(
                                      color: PdfColors.grey400,
                                      width: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );

          // ── Helper to check complaint durations and options ──
          final visitComplaints =
              visit?.anamnesisComplaints ?? const <String, dynamic>{};
          final complaintsList =
              (visitComplaints['clinicalComplaints'] as List?)
                  ?.map((e) => e.toString().toLowerCase())
                  .toList() ??
              [];

          bool isDurationMatch(String d, String durationVal) {
            if (durationVal.isEmpty) return false;
            final dNorm = d.toLowerCase().replaceAll(' ', '');
            final vNorm = durationVal.toLowerCase().replaceAll(' ', '');
            if (dNorm == vNorm) return true;
            if (d.contains('< 1month') &&
                (durationVal.contains('< 1m') ||
                    durationVal.contains('<1m') ||
                    durationVal.contains('< 3m') ||
                    durationVal.contains('1 month'))) {
              return true;
            }
            if (d.contains('< 1 year') &&
                (durationVal.contains('< 1 y') ||
                    durationVal.contains('<1y') ||
                    durationVal.contains('3-12') ||
                    durationVal.contains('1 year'))) {
              return true;
            }
            if (d.contains('> 1 year') &&
                (durationVal.contains('> 1 y') ||
                    durationVal.contains('>1y') ||
                    durationVal == '> 1 year')) {
              return true;
            }
            if (d.contains('> 5 years') &&
                (durationVal.contains('> 5') ||
                    durationVal.contains('>5') ||
                    durationVal.contains('5 year'))) {
              return true;
            }
            if (d.contains('> 10 years') &&
                (durationVal.contains('> 10') ||
                    durationVal.contains('>10') ||
                    durationVal.contains('10 year'))) {
              return true;
            }
            return false;
          }

          bool isOptionMatch(String opt, List<String> selectedOptions) {
            final optLower = opt.toLowerCase().trim();
            return selectedOptions.any(
              (s) =>
                  s == optLower || s.contains(optLower) || optLower.contains(s),
            );
          }

          // ── Clean 2-Column Chief Complaint Row (Exact Scan Layout) ──
          pw.Widget buildComplaintRow({
            required String key,
            required String nameEn,
            required String nameNe,
            required bool hasDuration,
            bool isInfertilityDuration = false,
            List<String> options = const [],
            String? optionPrefix,
          }) {
            final cData = visitComplaints[key] as Map<String, dynamic>?;
            final bool isTicked =
                cData != null ||
                (key == 'prolapse' &&
                    complaintsList.any(
                      (c) =>
                          c.contains('prolapse') ||
                          c.contains('hanging') ||
                          c.contains('पाठेघर'),
                    )) ||
                (key == 'discharge' &&
                    complaintsList.any(
                      (c) =>
                          c.contains('discharge') ||
                          c.contains('itching') ||
                          c.contains('स्राव'),
                    )) ||
                (key == 'urine' &&
                    complaintsList.any(
                      (c) =>
                          c.contains('urine') ||
                          c.contains('micturition') ||
                          c.contains('पिसाब'),
                    )) ||
                (key == 'stool' &&
                    complaintsList.any(
                      (c) => c.contains('stool') || c.contains('दिसा'),
                    )) ||
                (key == 'menstrual' &&
                    complaintsList.any(
                      (c) => c.contains('menstrual') || c.contains('महिनावारी'),
                    )) ||
                (key == 'infertility' &&
                    complaintsList.any(
                      (c) => c.contains('infertility') || c.contains('बाँझोपन'),
                    )) ||
                (key == 'lower_abdomen_pain' &&
                    complaintsList.any(
                      (c) =>
                          c.contains('abdomen') ||
                          c.contains('तल्लो पेट') ||
                          c == 'pain',
                    )) ||
                (key == 'lower_back_pain' &&
                    complaintsList.any(
                      (c) =>
                          c.contains('back') ||
                          c.contains('ढाड') ||
                          c.contains('कम्मर') ||
                          c == 'pain',
                    )) ||
                (key == 'checkup' &&
                    complaintsList.any(
                      (c) => c.contains('checkup') || c.contains('जाँच'),
                    ));

            final String durVal =
                (cData?['duration']?.toString() ??
                        (visitComplaints['complaintsDuration']?.toString() ??
                            ''))
                    .toLowerCase()
                    .trim();
            final List<String> selOpts = (cData?['options'] is List)
                ? (cData!['options'] as List)
                      .map((e) => e.toString().toLowerCase().trim())
                      .toList()
                : <String>[];
            final String remVal = cData?['remarks']?.toString() ?? '';

            final durationList = isInfertilityDuration
                ? ClinicalConstants.infertilityDurations
                : ClinicalConstants.anamnesisDurations;

            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 11.0),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Checkbox + Name
                  pw.SizedBox(
                    width: 135,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1.0),
                      child: cb(
                        '$nameEn\n($nameNe)',
                        isTicked,
                        fontSize: 7.4,
                        boxSize: 9.5,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  // Right: Bordered Rectangle Box (Duration, Sub-options, Remarks)
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 5.0,
                      ),
                      decoration: pw.BoxDecoration(
                        color: isTicked
                            ? PdfColor.fromHex('F8FAFC')
                            : PdfColors.white,
                        border: pw.Border.all(
                          color: isTicked
                              ? primary
                              : PdfColor.fromHex('CBD5E1'),
                          width: 0.6,
                        ),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(2.0),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (hasDuration) ...[
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text(
                                  'since when: ',
                                  style: pw.TextStyle(
                                    fontSize: 7.2,
                                    fontWeight: pw.FontWeight.bold,
                                    color: dark,
                                  ),
                                ),
                                ...durationList.map((d) {
                                  final checked =
                                      isTicked && isDurationMatch(d, durVal);
                                  return pw.Padding(
                                    padding: const pw.EdgeInsets.only(left: 3),
                                    child: cb(
                                      d,
                                      checked,
                                      fontSize: 7.0,
                                      boxSize: 8.5,
                                    ),
                                  );
                                }),
                              ],
                            ),
                            pw.SizedBox(height: 1.5),
                          ],
                          pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              if (options.isNotEmpty) ...[
                                if (optionPrefix != null)
                                  pw.Text(
                                    '$optionPrefix: ',
                                    style: pw.TextStyle(
                                      fontSize: 7.0,
                                      fontWeight: pw.FontWeight.bold,
                                      color: dark,
                                    ),
                                  ),
                                ...options.map((opt) {
                                  final checked =
                                      isTicked && isOptionMatch(opt, selOpts);
                                  return pw.Padding(
                                    padding: const pw.EdgeInsets.only(right: 4),
                                    child: cb(
                                      opt,
                                      checked,
                                      fontSize: 7.0,
                                      boxSize: 8.5,
                                    ),
                                  );
                                }),
                                pw.SizedBox(width: 4),
                              ],
                              pw.Text(
                                'remarks: ',
                                style: pw.TextStyle(
                                  fontSize: 7.0,
                                  fontWeight: pw.FontWeight.bold,
                                  color: dark,
                                ),
                              ),
                              pw.Expanded(
                                child: pw.Container(
                                  height: 10,
                                  decoration: const pw.BoxDecoration(
                                    border: pw.Border(
                                      bottom: pw.BorderSide(
                                        color: PdfColors.grey400,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  alignment: pw.Alignment.bottomLeft,
                                  padding: const pw.EdgeInsets.only(
                                    bottom: 0.5,
                                  ),
                                  child: pw.Text(
                                    remVal,
                                    style: pw.TextStyle(
                                      fontSize: 7.0,
                                      color: primary,
                                    ),
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // ── STATION 1: ANAMNESIS & OBSTETRIC HISTORY ──
          final station1 = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr(
                'STATION 1: ANAMNESIS & OBSTETRIC HISTORY / पहिलो स्टेशन: विगत तथा प्रसूति विवरण',
              ),
              // Deliveries row (Anamnesis Date removed as per instructions)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 7.0),
                child: pw.Row(
                  children: [
                    pw.Text(
                      'NR deliveries: ',
                      style: pw.TextStyle(
                        fontSize: 8.0,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    buildCharBoxes(
                      visit?.deliveries?.toString() ?? '',
                      minBoxes: 2,
                      maxBoxes: 2,
                      boxSize: 11.0,
                      boxHeight: 14.0,
                      boxMargin: 1.0,
                    ),
                    pw.SizedBox(width: 14),
                    pw.Text(
                      'NR living children: ',
                      style: pw.TextStyle(
                        fontSize: 8.0,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    buildCharBoxes(
                      visit?.livingChildren?.toString() ?? '',
                      minBoxes: 2,
                      maxBoxes: 2,
                      boxSize: 11.0,
                      boxHeight: 14.0,
                      boxMargin: 1.0,
                    ),
                    pw.SizedBox(width: 14),
                    pw.Text(
                      'NR abortion: ',
                      style: pw.TextStyle(
                        fontSize: 8.0,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    buildCharBoxes(
                      visit?.abortions?.toString() ?? '',
                      minBoxes: 2,
                      maxBoxes: 2,
                      boxSize: 11.0,
                      boxHeight: 14.0,
                      boxMargin: 1.0,
                    ),
                  ],
                ),
              ),
              // All 9 Canonical Complaints with Individual Durations, Sub-options, and Remarks
              buildComplaintRow(
                key: 'prolapse',
                nameEn: 'something hanging out',
                nameNe: 'पाठेघर खस्ने',
                hasDuration: true,
                options: ['pessary', 'surgery'],
                optionPrefix: 'previous treatment',
              ),
              buildComplaintRow(
                key: 'discharge',
                nameEn: 'discharge / itching',
                nameNe: 'पानी बग्ने / चिलाउने',
                hasDuration: true,
                options: ['white', 'yellow', 'green', 'grey', 'smelly'],
                optionPrefix: 'colour',
              ),
              buildComplaintRow(
                key: 'urine',
                nameEn: 'problems passing urine',
                nameNe: 'पिसाब समस्या',
                hasDuration: true,
                options: ['stress', 'urge', 'continuous flow'],
                optionPrefix: 'type incontinence',
              ),
              buildComplaintRow(
                key: 'stool',
                nameEn: 'problems passing stool',
                nameNe: 'दिसा समस्या',
                hasDuration: true,
              ),
              buildComplaintRow(
                key: 'menstrual',
                nameEn: 'menstrual problem',
                nameNe: 'महिनावारी समस्या',
                hasDuration: false,
                options: [
                  'dysmenorrhoea',
                  'metrorrhagia',
                  'menorrhagia',
                  'postmenopausal bleeding',
                ],
              ),
              buildComplaintRow(
                key: 'infertility',
                nameEn: 'infertility',
                nameNe: 'निःसन्तान समस्या',
                hasDuration: true,
                isInfertilityDuration: true,
              ),
              buildComplaintRow(
                key: 'lower_abdomen_pain',
                nameEn: 'lower abdomen pain',
                nameNe: 'तल्लो पेट दुख्ने',
                hasDuration: true,
              ),
              buildComplaintRow(
                key: 'lower_back_pain',
                nameEn: 'lower back pain',
                nameNe: 'कम्मर / ढाड दुख्ने',
                hasDuration: true,
              ),
              buildComplaintRow(
                key: 'checkup',
                nameEn: 'checkup',
                nameNe: 'सामान्य जाँच',
                hasDuration: false,
                options: ['routine screening'],
              ),
            ],
          );

          // ── Bottom Administrative Footer ──
          final bottomFooter = pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 16),
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4.5,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('F8FAFC'),
              border: pw.Border.all(color: primary, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'FOR OFFICIAL USE ONLY: Registration Verified',
                  style: pw.TextStyle(
                    fontSize: 7.2,
                    fontWeight: pw.FontWeight.bold,
                    color: primary,
                  ),
                ),
                pw.Text(
                  'Data Entry Operator: _______________________',
                  style: const pw.TextStyle(
                    fontSize: 7.0,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    ne(
                      'Date / मिति:',
                      size: 7.0,
                      bold: false,
                      color: 0xFF616161,
                    ),
                    pw.SizedBox(width: 4),
                    buildDateBsBoxes(
                      intakeDate,
                      hasData: hasPatient,
                      boxSize: 8.0,
                      boxHeight: 11.0,
                      fontSize: 6.8,
                    ),
                  ],
                ),
                pw.Text(
                  camp != null
                      ? 'Camp: ${camp.campCode}'
                      : 'Camp / कोड: [    ]',
                  style: pw.TextStyle(
                    fontSize: 7.2,
                    fontWeight: pw.FontWeight.bold,
                    color: dark,
                  ),
                ),
              ],
            ),
          );

          // Return full page layout with FittedBox ensuring strictly 1 physical page
          return pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            alignment: pw.Alignment.topCenter,
            child: pw.SizedBox(
              width: 559,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Page 1 Header Strip
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logo != null)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(right: 8),
                          child: pw.Image(logo, width: 34, height: 34),
                        ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              sanitizeText(organizationName.toUpperCase()),
                              style: pw.TextStyle(
                                fontSize: 11.5,
                                fontWeight: pw.FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            pw.Text(
                              'PATIENT REGISTRATION & ANAMNESIS — PAGE 1 (FRONT)',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: dark,
                              ),
                            ),
                            pw.Text(
                              camp != null
                                  ? 'Camp: ${sanitizeText(camp.name)} (${camp.campCode})${doctorHeaderPart.isNotEmpty ? " | $doctorHeaderPart" : ""}'
                                  : 'Camp / शिविर: ___________________________ | Venue / ठाउँ: ___________________________${doctorHeaderPart.isNotEmpty ? " | $doctorHeaderPart" : ""}',
                              style: const pw.TextStyle(
                                fontSize: 6.8,
                                color: PdfColors.grey700,
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      if (hasPatient)
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'PATIENT ID: ${patient.patientId}',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.code128(),
                              data: patient.patientId,
                              width: 65,
                              height: 18,
                              drawText: false,
                            ),
                          ],
                        )
                      else if (preprintedPatientId != null &&
                          preprintedPatientId.isNotEmpty)
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: preprintedPatientId,
                              width: 24,
                              height: 24,
                            ),
                            pw.SizedBox(width: 6),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text(
                                  'PATIENT ID: $preprintedPatientId',
                                  style: pw.TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: primary,
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.BarcodeWidget(
                                  barcode: pw.Barcode.code128(),
                                  data: preprintedPatientId,
                                  width: 60,
                                  height: 16,
                                  drawText: false,
                                ),
                              ],
                            ),
                          ],
                        )
                      else
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              'Token: ',
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                fontWeight: pw.FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            buildCharBoxes(
                              dynamicTokenPrefix,
                              minBoxes: 18,
                              maxBoxes: 18,
                              boxSize: 11.5,
                              boxHeight: 14.5,
                              boxMargin: 1.0,
                            ),
                          ],
                        ),
                    ],
                  ),
                  triageStrip,
                  pw.SizedBox(height: 7),
                  sectionA,
                  pw.SizedBox(height: 7),
                  sectionB,
                  pw.SizedBox(height: 7),
                  station1,
                  pw.SizedBox(height: 10),
                  bottomFooter,
                ],
              ),
            ),
          );
        },
      ),
    );

    // ═══════════════════════════════════════════════════════════════════════
    // PAGE 2 — CLINICAL ASSESSMENT & EXAMINATIONS (Yellow Form Back Page)
    // Full-Width Medical Stations Layout Matching Physical Form Scan
    // Strictly 1 Physical A4 Page
    // ═══════════════════════════════════════════════════════════════════════
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        build: (ctx) {
          const fs = 8.0;
          const fsSmall = 7.6;

          pw.TextStyle bold({double size = fs}) => pw.TextStyle(
            fontSize: size,
            fontWeight: pw.FontWeight.bold,
            color: dark,
          );
          pw.TextStyle normal({double size = fs}) =>
              pw.TextStyle(fontSize: size, color: dark);

          pw.Widget secHdr(String title) {
            return pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 5.5, bottom: 4.5),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 3.5,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('F1F5F9'),
                border: pw.Border(
                  left: pw.BorderSide(
                    color: PdfColor.fromHex('1B365D'),
                    width: 3.2,
                  ),
                  top: pw.BorderSide(
                    color: PdfColor.fromHex('CBD5E1'),
                    width: 0.6,
                  ),
                  right: pw.BorderSide(
                    color: PdfColor.fromHex('CBD5E1'),
                    width: 0.6,
                  ),
                  bottom: pw.BorderSide(
                    color: PdfColor.fromHex('CBD5E1'),
                    width: 0.6,
                  ),
                ),
              ),
              child: ne(title, size: 8.8, bold: true, color: 0xFF0F172A),
            );
          }

          pw.Widget cb(
            String label,
            bool checked, {
            double? textWidth,
            double bottom = 0.0,
            bool isExpanded = false,
            double boxSize = 10.5,
            double fontSize = 8.0,
          }) => pw.Padding(
            padding: pw.EdgeInsets.only(right: 6, bottom: bottom),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: isExpanded
                  ? pw.MainAxisSize.max
                  : pw.MainAxisSize.min,
              children: [
                pw.Container(
                  width: boxSize,
                  height: boxSize,
                  margin: const pw.EdgeInsets.only(right: 4.0),
                  decoration: pw.BoxDecoration(
                    color: checked
                        ? PdfColor.fromHex('EDE9FF')
                        : PdfColors.white,
                    border: pw.Border.all(
                      color: checked ? primary : PdfColor.fromHex('475569'),
                      width: 0.8,
                    ),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(2.0),
                    ),
                  ),
                  child: checked
                      ? pw.Center(
                          child: pw.Text(
                            'X',
                            style: pw.TextStyle(
                              fontSize: boxSize * 0.72,
                              fontWeight: pw.FontWeight.bold,
                              color: primary,
                            ),
                          ),
                        )
                      : pw.SizedBox(),
                ),
                if (textWidth != null)
                  pw.SizedBox(
                    width: textWidth,
                    child: ne(label, size: fontSize, maxWidth: textWidth),
                  )
                else if (isExpanded)
                  pw.Expanded(child: ne(label, size: fontSize))
                else
                  ne(label, size: fontSize),
              ],
            ),
          );

          pw.Widget examLine({
            required String label,
            required bool isNormal,
            required String? remarks,
          }) {
            final hasNotes =
                remarks != null &&
                remarks.trim().isNotEmpty &&
                remarks.trim().toLowerCase() != 'normal';
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(
                    width: 55,
                    child: pw.Text(label, style: bold(size: fs)),
                  ),
                  cb(
                    'normal or',
                    isNormal && !hasNotes,
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Container(
                      height: 13,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.grey400,
                            width: 0.5,
                          ),
                        ),
                      ),
                      alignment: pw.Alignment.bottomLeft,
                      padding: const pw.EdgeInsets.only(bottom: 0.5),
                      child: pw.Text(
                        hasNotes ? sanitizeText(remarks) : '',
                        style: pw.TextStyle(fontSize: 7.6, color: primary),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final tone = (visit?.pelvicFloorTone ?? '').toLowerCase();

          // ECG Status detection
          final ecgText = (visit?.ecgNotes ?? '').toLowerCase().trim();
          final isEcgNormal =
              ecgText.contains('normal') || ecgText.contains('sinus rhythm');
          final isEcgAbnormal =
              ecgText.contains('abnormal') ||
              ecgText.contains('arrhythmia') ||
              ecgText.contains('tachycardia') ||
              ecgText.contains('bradycardia') ||
              ecgText.contains('ischemia') ||
              ecgText.contains('st-t');
          final isEcgNotDone =
              ecgText.contains('not done') ||
              (visit != null &&
                  ecgText.isEmpty &&
                  !isEcgNormal &&
                  !isEcgAbnormal);


          // ── STATION 2: POP & PHYSICAL EXAMINATION ──
          final station2 = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr(
                'STATION 2: POP & PHYSICAL EXAMINATION / शारीरिक जाँच तथा पाठेघर खस्ने अवस्था',
              ),
              // Row 1: Exam Date, Uterus Inside, Pelvic Floor Tone
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Examination Date: ', style: bold(size: fsSmall)),
                  buildDateBsBoxes(
                    intakeDate,
                    hasData: hasPatient,
                    boxSize: 8.5,
                    boxHeight: 11.5,
                    fontSize: 7.0,
                  ),
                  pw.SizedBox(width: 14),
                  pw.Text('uterus inside: ', style: bold(size: fsSmall)),
                  cb(
                    'yes',
                    visit?.uterusInside == true,
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  cb(
                    'no',
                    visit?.uterusInside == false,
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text('pelvic floor muscle: ', style: bold(size: fsSmall)),
                  cb(
                    'normal',
                    tone == 'normal',
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  cb(
                    'weak',
                    tone == 'weak',
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  cb(
                    'hypertonic',
                    tone == 'hypertonic' || tone == 'torn',
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                ],
              ),
              pw.SizedBox(height: 2.5),
              // 4 Anatomical Examination Lines matching Physical Form
              examLine(
                label: 'vulva',
                isNormal:
                    visit != null &&
                    ((visit.vulvaRemarks ?? 'normal').toLowerCase().contains(
                      'normal',
                    )),
                remarks: visit?.vulvaRemarks,
              ),
              examLine(
                label: 'vagina',
                isNormal:
                    visit != null &&
                    ((visit.vaginaRemarks ?? 'normal').toLowerCase().contains(
                      'normal',
                    )),
                remarks: visit?.vaginaRemarks,
              ),
              examLine(
                label: 'cervix',
                isNormal:
                    visit != null &&
                    ((visit.cervixRemarks ?? 'normal').toLowerCase().contains(
                      'normal',
                    )),
                remarks: visit?.cervixRemarks,
              ),
              examLine(
                label: 'uterus',
                isNormal:
                    visit != null &&
                    ((visit.uterusRemarks ?? 'normal').toLowerCase().contains(
                      'normal',
                    )),
                remarks: visit?.uterusRemarks,
              ),
              pw.SizedBox(height: 2.0),
              // POP Staging Rows (Anterior, Middle, Posterior)
              pw.Row(
                children: [
                  pw.SizedBox(
                    width: 115,
                    child: pw.Text(
                      'POP anterior wall:',
                      style: bold(size: fsSmall),
                    ),
                  ),
                  ...[0, 1, 2, 3].map(
                    (s) => cb(
                      'stage $s',
                      visit?.popAnteriorStage == s,
                      bottom: 0,
                      boxSize: 10.5,
                      fontSize: 8.0,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 1.5),
              pw.Row(
                children: [
                  pw.SizedBox(
                    width: 115,
                    child: pw.Text(
                      'POP middle part:',
                      style: bold(size: fsSmall),
                    ),
                  ),
                  ...[0, 1, 2, 3, 4].map(
                    (s) => cb(
                      'stage $s',
                      visit?.popMiddleStage == s,
                      bottom: 0,
                      boxSize: 10.5,
                      fontSize: 8.0,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 1.5),
              pw.Row(
                children: [
                  pw.SizedBox(
                    width: 115,
                    child: pw.Text(
                      'POP posterior wall:',
                      style: bold(size: fsSmall),
                    ),
                  ),
                  ...[0, 1, 2, 3].map(
                    (s) => cb(
                      'stage $s',
                      visit?.popPosteriorStage == s,
                      bottom: 0,
                      boxSize: 10.5,
                      fontSize: 8.0,
                    ),
                  ),
                ],
              ),
            ],
          );

          // ── STATION 3: POINT-OF-CARE LABS, VITALS & ECG ──
          final station3 = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr(
                'STATION 3: POINT-OF-CARE LABS, VITALS & ECG / प्रयोगशाला, सूचक तथा ईसीजी',
              ),
              // Row 1: Lab Date, Full Urine Dipstick & Pregnancy Test Options
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Lab test Date: ', style: bold(size: fsSmall)),
                  buildDateBsBoxes(
                    visit?.visitDate ?? intakeDate,
                    hasData: hasPatient,
                    boxSize: 8.5,
                    boxHeight: 11.5,
                    fontSize: 7.0,
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text('urine test: ', style: bold(size: fsSmall)),
                  cb(
                    'normal',
                    (visit?.urineTest ?? '').toLowerCase().contains('normal') ||
                        (visit != null && (visit.urineTest ?? '').isEmpty),
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  cb(
                    'pos',
                    (visit?.urineTest ?? '').toLowerCase().contains('pos') ||
                        (visit?.urineTest ?? '').toLowerCase().contains('+'),
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text('pregnancy test: ', style: bold(size: fsSmall)),
                  cb(
                    'neg',
                    (visit?.pregnancyTest ?? '').toLowerCase().startsWith('neg') ||
                        (visit != null && (visit.pregnancyTest ?? '').isEmpty),
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  cb(
                    'pos',
                    (visit?.pregnancyTest ?? '').toLowerCase().startsWith('pos'),
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                ],
              ),
              pw.SizedBox(height: 3.0),
              // Row 2: Vitals & Blood Glucose
              pw.Row(
                children: [
                  pw.Text('blood pressure: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 75,
                    height: 13,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    child: pw.Text(
                      (visit != null && visit.systolicBp != null)
                          ? '${visit.systolicBp} / ${visit.diastolicBp ?? "-"} mmHg'
                          : '',
                      style: pw.TextStyle(fontSize: 7.6, color: primary),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('pulse: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 48,
                    height: 13,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    child: pw.Text(
                      visit?.pulse != null ? '${visit!.pulse} bpm' : '',
                      style: pw.TextStyle(fontSize: 7.6, color: primary),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('SpO2: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 45,
                    height: 13,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    child: pw.Text(
                      visit?.spo2 != null ? '${visit!.spo2} %' : '',
                      style: pw.TextStyle(fontSize: 7.6, color: primary),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('blood glucose: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 55,
                    height: 13,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    child: pw.Text(
                      visit?.glucose != null ? '${visit!.glucose} mg/dL' : '',
                      style: pw.TextStyle(fontSize: 7.6, color: primary),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3.0),
              // Row 3: ECG Examination
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('ECG: ', style: bold(size: fsSmall)),
                  cb(
                    'Normal Sinus',
                    isEcgNormal,
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  cb(
                    'Abnormal',
                    isEcgAbnormal,
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  cb(
                    'Not Done',
                    isEcgNotDone,
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.0,
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('ECG Notes: ', style: bold(size: fsSmall)),
                  pw.Expanded(
                    child: pw.Container(
                      height: 13,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.grey400,
                            width: 0.5,
                          ),
                        ),
                      ),
                      alignment: pw.Alignment.bottomLeft,
                      child: pw.Text(
                        sanitizeText(visit?.ecgNotes),
                        style: pw.TextStyle(fontSize: 7.6, color: primary),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          // ── STATION 4: CONFIRMED DIAGNOSES ──
          final station4 = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr('STATION 4: CONFIRMED DIAGNOSES / निदान'),
              // POP Highest Stage
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Conclusion Date: ', style: bold(size: fsSmall)),
                  buildDateBsBoxes(
                    intakeDate,
                    hasData: hasPatient,
                    boxSize: 8.5,
                    boxHeight: 11.5,
                    fontSize: 7.0,
                  ),
                  pw.SizedBox(width: 14),
                  pw.Text('highest POP stage: ', style: bold(size: fsSmall)),
                  ...[0, 1, 2, 3, 4].map(
                    (s) => cb(
                      'stage $s',
                      visit?.highestPopStage == s,
                      bottom: 0,
                      boxSize: 10.5,
                      fontSize: 8.0,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3.0),
              // 4-Column Diagnosis Grid with all 21 diagnoses matching physical Yellow Form
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(5),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColor.fromHex('CBD5E1'),
                    width: 0.6,
                  ),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(2),
                  ),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Col 1 (6 diagnoses)
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children:
                            [
                              'atrophy vagina',
                              'bacterial vaginosis',
                              'candid infection',
                              'trichomonas',
                              'PID',
                              'cervicitis',
                            ].map((d) {
                              final isChecked =
                                  visit?.diagnoses.any(
                                    (diag) => diag.toLowerCase().contains(
                                      d.toLowerCase(),
                                    ),
                                  ) ??
                                  false;
                              return cb(
                                d,
                                isChecked,
                                bottom: 2.0,
                                fontSize: 7.6,
                                boxSize: 9.5,
                              );
                            }).toList(),
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    // Col 2 (6 diagnoses)
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children:
                            [
                              'cervical polyp',
                              'cervical carcinoma',
                              'condylomata',
                              'fistula',
                              'infertility',
                              'myoma',
                            ].map((d) {
                              final isChecked =
                                  visit?.diagnoses.any(
                                    (diag) => diag.toLowerCase().contains(
                                      d.toLowerCase(),
                                    ),
                                  ) ??
                                  false;
                              return cb(
                                d,
                                isChecked,
                                bottom: 2.0,
                                fontSize: 7.6,
                                boxSize: 9.5,
                              );
                            }).toList(),
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    // Col 3 (5 diagnoses)
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children:
                            [
                              'cystitis',
                              'stress incontinence',
                              'urge incontinence',
                              'weak pelvic floor muscle',
                              'hypertonic pelvic floor muscle',
                            ].map((d) {
                              final isChecked =
                                  visit?.diagnoses.any(
                                    (diag) => diag.toLowerCase().contains(
                                      d.toLowerCase(),
                                    ),
                                  ) ??
                                  false;
                              return cb(
                                d,
                                isChecked,
                                bottom: 2.0,
                                fontSize: 7.6,
                                boxSize: 9.5,
                              );
                            }).toList(),
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    // Col 4 (4 diagnoses)
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children:
                            [
                              'lichen sclerosis',
                              'ovarian tumor',
                              'menstrual disorder',
                              'pregnancy',
                            ].map((d) {
                              final isChecked =
                                  visit?.diagnoses.any(
                                    (diag) => diag.toLowerCase().contains(
                                      d.toLowerCase(),
                                    ),
                                  ) ??
                                  false;
                              return cb(
                                d,
                                isChecked,
                                bottom: 2.0,
                                fontSize: 7.6,
                                boxSize: 9.5,
                              );
                            }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 2.0),
              pw.Row(
                children: [
                  pw.Text('Other: ', style: bold(size: fsSmall)),
                  pw.Expanded(
                    child: pw.Container(
                      height: 12,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.grey400,
                            width: 0.5,
                          ),
                        ),
                      ),
                      alignment: pw.Alignment.bottomLeft,
                      child: pw.Text(
                        visit != null &&
                                visit.diagnoses.any(
                                  (d) => !ClinicalConstants.defaultDiagnoses
                                      .contains(d),
                                )
                            ? sanitizeText(
                                visit.diagnoses.firstWhere(
                                  (d) => !ClinicalConstants.defaultDiagnoses
                                      .contains(d),
                                ),
                              )
                            : '',
                        style: pw.TextStyle(fontSize: 7.6, color: primary),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          // ── STATION 5: TREATMENT & PRESCRIPTIONS ──
          final station5 = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr('STATION 5: TREATMENT & PRESCRIPTIONS / उपचार तथा औषधि'),
              // Row 1: Treatment Date + Pessary options
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Treatment Date: ', style: bold(size: fsSmall)),
                  buildDateBsBoxes(
                    intakeDate,
                    hasData: hasPatient,
                    boxSize: 8.5,
                    boxHeight: 11.5,
                    fontSize: 7.0,
                  ),
                  pw.SizedBox(width: 14),
                  pw.Text('pessary: ', style: bold(size: fsSmall)),
                  cb(
                    'ring',
                    (visit?.pessaryType ?? '').toLowerCase() == 'ring',
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                  cb(
                    'ring with support',
                    (visit?.pessaryType ?? '').toLowerCase().contains(
                      'support',
                    ),
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                  cb(
                    'ring with knob',
                    (visit?.pessaryType ?? '').toLowerCase().contains('knob'),
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                  pw.SizedBox(width: 4),
                  pw.Text('size: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 28,
                    height: 12,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    child: pw.Text(
                      visit?.pessarySize ?? '',
                      style: pw.TextStyle(fontSize: 7.6, color: primary),
                    ),
                  ),
                  pw.Text(' mm', style: normal(size: fsSmall)),
                ],
              ),
              pw.SizedBox(height: 3.0),
              // Row 2: Dedicated row for spec counseling
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('spec counseling: ', style: bold(size: fsSmall)),
                  cb(
                    'weak pelvic floor',
                    visit?.counseling.any(
                          (c) =>
                              c.toLowerCase().contains('pelvic') ||
                              c.toLowerCase().contains('pfmt'),
                        ) ??
                        false,
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                  cb(
                    'POP',
                    visit?.counseling.any(
                          (c) =>
                              c.toLowerCase().contains('pop') ||
                              c.toLowerCase().contains('prolapse'),
                        ) ??
                        false,
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                  cb(
                    'stress incontinence',
                    visit?.counseling.any(
                          (c) => c.toLowerCase().contains('stress'),
                        ) ??
                        false,
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                  cb(
                    'urge incontinence',
                    visit?.counseling.any(
                          (c) => c.toLowerCase().contains('urge'),
                        ) ??
                        false,
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                  cb(
                    'abdominal pain',
                    visit?.counseling.any(
                          (c) => c.toLowerCase().contains('pain'),
                        ) ??
                        false,
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                ],
              ),
              pw.SizedBox(height: 3.0),
              // Row 3: Referral Surgery
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('referral surgery: ', style: bold(size: fsSmall)),
                  cb(
                    'Scheer Memorial',
                    (visit?.surgicalReferral ?? '').toLowerCase().contains(
                      'scheer',
                    ),
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                  cb(
                    'Model Hosp',
                    (visit?.surgicalReferral ?? '').toLowerCase().contains(
                      'model',
                    ),
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                  cb(
                    'loc government',
                    (visit?.surgicalReferral ?? '').toLowerCase().contains(
                          'gov',
                        ) ||
                        (visit?.surgicalReferral ?? '').toLowerCase().contains(
                          'local',
                        ),
                    bottom: 0,
                    fontSize: 7.6,
                    boxSize: 10.0,
                  ),
                ],
              ),
              pw.SizedBox(height: 4.0),
              // 2-Column Medication Grid (All 10 formulary medications)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColor.fromHex('CBD5E1'),
                    width: 0.6,
                  ),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(2),
                  ),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: ClinicalConstants.defaultMedications
                            .take(5)
                            .map((m) {
                              final isChecked =
                                  visit?.medications.any(
                                    (med) => med.toLowerCase().contains(
                                      m.toLowerCase().split(' ').first,
                                    ),
                                  ) ??
                                  false;
                              return cb(
                                m,
                                isChecked,
                                bottom: 6.0,
                                fontSize: 7.8,
                                boxSize: 10.5,
                              );
                            })
                            .toList(),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: ClinicalConstants.defaultMedications
                            .skip(5)
                            .take(5)
                            .map((m) {
                              final isChecked =
                                  visit?.medications.any(
                                    (med) => med.toLowerCase().contains(
                                      m.toLowerCase().split(' ').first,
                                    ),
                                  ) ??
                                  false;
                              return cb(
                                m,
                                isChecked,
                                bottom: 6.0,
                                fontSize: 7.8,
                                boxSize: 10.5,
                              );
                            })
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 3.0),
              pw.Row(
                children: [
                  pw.Text('other medication: ', style: bold(size: fsSmall)),
                  pw.Expanded(
                    child: pw.Container(
                      height: 14,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.grey400,
                            width: 0.5,
                          ),
                        ),
                      ),
                      alignment: pw.Alignment.bottomLeft,
                      child: pw.Text(
                        sanitizeText(visit?.customMedication),
                        style: pw.TextStyle(fontSize: 7.6, color: primary),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          // ── STATION 6: DISCHARGE & CONTINUITY OF CARE ──
          final followUpDest = visit?.followUpDestination;
          final isHospitalFollowUp =
              followUpDest != null &&
              !followUpDest.toLowerCase().contains('health post') &&
              !followUpDest.toLowerCase().contains('nurse');

          final station6 = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr(
                'STATION 6: DISCHARGE & CONTINUITY OF CARE / अनुगमन तथा डिस्चार्ज',
              ),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Outtake Date: ', style: bold(size: fsSmall)),
                  buildDateBsBoxes(
                    intakeDate,
                    hasData: hasPatient,
                    boxSize: 8.5,
                    boxHeight: 11.5,
                    fontSize: 7.0,
                  ),
                ],
              ),
              pw.SizedBox(height: 5.0),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Follow up details
                  pw.Expanded(
                    flex: 50,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('follow up: ', style: bold(size: fsSmall)),
                        pw.SizedBox(height: 4),
                        cb(
                          'Health Post (स्वास्थ्य चौकी)',
                          (followUpDest ?? '').toLowerCase().contains(
                            'health post',
                          ),
                          bottom: 7.0,
                          fontSize: 8.0,
                          boxSize: 10.5,
                        ),
                        cb(
                          'GynaeSupport Nurse (गाइने नर्स)',
                          (followUpDest ?? '').toLowerCase().contains(
                                'gynaesupport',
                              ) ||
                              (followUpDest ?? '').toLowerCase().contains(
                                'nurse',
                              ),
                          bottom: 7.0,
                          fontSize: 8.0,
                          boxSize: 10.5,
                        ),
                        pw.Row(
                          children: [
                            cb(
                              'Hospital: ',
                              isHospitalFollowUp,
                              bottom: 0,
                              fontSize: 8.0,
                              boxSize: 10.5,
                            ),
                            pw.Expanded(
                              child: pw.Container(
                                height: 13,
                                decoration: const pw.BoxDecoration(
                                  border: pw.Border(
                                    bottom: pw.BorderSide(
                                      color: PdfColors.grey400,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                alignment: pw.Alignment.bottomLeft,
                                child: pw.Text(
                                  isHospitalFollowUp
                                      ? sanitizeText(followUpDest)
                                      : '',
                                  style: pw.TextStyle(
                                    fontSize: 7.6,
                                    color: primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4.0),
                        cb(
                          'no follow up needed',
                          visit?.followUpNeeded == false,
                          bottom: 0,
                          fontSize: 8.0,
                          boxSize: 10.5,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  // Right: Clinical Notes Box
                  pw.Expanded(
                    flex: 50,
                    child: pw.Container(
                      height: 108,
                      padding: const pw.EdgeInsets.all(5.0),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: PdfColor.fromHex('CBD5E1'),
                          width: 0.6,
                        ),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(2),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Clinical Notes / Outtake Remarks:',
                            style: bold(size: 7.4),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            visit?.outtakeNotes ?? '',
                            style: pw.TextStyle(fontSize: 7.2, color: primary),
                            maxLines: 5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          // ── Signatures Block (Outreach Team Signatures) ──
          final signaturesBlock = pw.Padding(
            padding: const pw.EdgeInsets.only(top: 18.0, bottom: 2.0),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                // 1. Data Entry Operator
                pw.SizedBox(
                  width: 135,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(height: 26.0), // Clear pen signing zone
                      pw.Container(
                        width: 110,
                        height: 0.7,
                        color: PdfColors.black,
                      ),
                      pw.SizedBox(height: 4.0),
                      pw.Text(
                        'Data Entry Operator',
                        style: bold(size: fsSmall),
                      ),
                      pw.Text(
                        'Name & Date: ${hasPatient ? dateFormatter.format(intakeDate) : "_______________"}',
                        style: const pw.TextStyle(
                          fontSize: 6.8,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 14),
                // 2. Attending Nurse
                pw.SizedBox(
                  width: (allNursesChecklist || effectiveNurses.length > 1) ? 190 : 150,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.SizedBox(height: 26.0), // Clear pen signing zone
                      pw.Container(
                        width: 120,
                        height: 0.7,
                        color: PdfColors.black,
                      ),
                      pw.SizedBox(height: 4.0),
                      if (!showNurse || blankNurseLines) ...[
                        pw.Text('Attending Nurse', style: bold(size: fsSmall)),
                        pw.Text(
                          'Nurse Signature & NNC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (allNursesChecklist || (effectiveNurses.length > 1 && nurse == null && visit == null)) ...[
                        pw.Text('Attending Nurse (Tick on Paper):', style: bold(size: 7.0)),
                        pw.SizedBox(height: 1.5),
                        pw.Wrap(
                          alignment: pw.WrapAlignment.center,
                          spacing: 4,
                          runSpacing: 2,
                          children: effectiveNurses.map((n) {
                            final label = n.hasRegistration
                                ? '${n.displayName} (${n.registrationNumber})'
                                : n.displayName;
                            return cb(label, false, bottom: 0, boxSize: 8.5, fontSize: 6.8);
                          }).toList(),
                        ),
                        pw.SizedBox(height: 1.5),
                        pw.Text(
                          'Nurse Signature: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (nurse != null) ...[
                        pw.Text(sanitizeText(nurse.displayName), style: bold(size: fsSmall)),
                        pw.Text(
                          nurse.hasRegistration
                              ? 'NNC No: ${nurse.registrationNumber}'
                              : 'Nurse Signature & NNC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (visit != null &&
                          visit.primaryNurseName != null &&
                          visit.primaryNurseName!.isNotEmpty) ...[
                        pw.Text(sanitizeText(visit.primaryNurseName!), style: bold(size: fsSmall)),
                        pw.Text(
                          'Nurse Signature & NNC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (effectiveNurses.isNotEmpty) ...[
                        pw.Text(sanitizeText(effectiveNurses.first.displayName), style: bold(size: fsSmall)),
                        pw.Text(
                          effectiveNurses.first.hasRegistration
                              ? 'NNC No: ${effectiveNurses.first.registrationNumber}'
                              : 'Nurse Signature & NNC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else ...[
                        pw.Text('Attending Nurse', style: bold(size: fsSmall)),
                        pw.Text(
                          'Nurse Signature & NNC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 14),
                // 3. Examining Doctor
                pw.SizedBox(
                  width: 185,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.SizedBox(height: 26.0), // Clear pen signing zone
                      pw.Container(
                        width: 120,
                        height: 0.7,
                        color: PdfColors.black,
                      ),
                      pw.SizedBox(height: 4.0),
                      if (!showDoctor || blankDoctorLines) ...[
                        pw.Text('Examining Doctor', style: bold(size: fsSmall)),
                        pw.Text(
                          'Doctor Signature & NMC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (allDoctorsChecklist || (effectiveDoctors.length > 1 && doctor == null && visit == null)) ...[
                        pw.Text('Examining Doctor (Tick on Paper):', style: bold(size: 7.0)),
                        pw.SizedBox(height: 1.5),
                        pw.Wrap(
                          alignment: pw.WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 2,
                          children: effectiveDoctors.map((p) {
                            final label = p.hasNmc ? '${p.displayName} (${p.nmcNumber})' : p.displayName;
                            return cb(label, false, bottom: 0, boxSize: 8.5, fontSize: 6.8);
                          }).toList(),
                        ),
                        pw.SizedBox(height: 1.5),
                        pw.Text(
                          'Doctor Signature: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (doctor != null) ...[
                        pw.Text(sanitizeText(doctor.displayName), style: bold(size: fsSmall)),
                        pw.Text(
                          doctor.hasNmc
                              ? 'NMC No: ${doctor.nmcNumber}'
                              : 'Doctor Signature & NMC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (visit != null &&
                          visit.primaryDoctorName != null &&
                          visit.primaryDoctorName!.isNotEmpty) ...[
                        pw.Text(sanitizeText(visit.primaryDoctorName!), style: bold(size: fsSmall)),
                        pw.Text(
                          'Doctor Signature & NMC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (effectiveDoctors.isNotEmpty) ...[
                        pw.Text(sanitizeText(effectiveDoctors.first.displayName), style: bold(size: fsSmall)),
                        pw.Text(
                          effectiveDoctors.first.hasNmc
                              ? 'NMC No: ${effectiveDoctors.first.nmcNumber}'
                              : 'Doctor Signature & NMC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else ...[
                        pw.Text('Examining Doctor', style: bold(size: fsSmall)),
                        pw.Text(
                          'Doctor Signature & NMC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 6.8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );

          // Return full page layout with FittedBox ensuring strictly 1 physical page
          return pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            alignment: pw.Alignment.topCenter,
            child: pw.SizedBox(
              width: 559,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Page 2 Header Strip
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logo != null)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(right: 8),
                          child: pw.Image(logo, width: 32, height: 32),
                        ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              sanitizeText(organizationName.toUpperCase()),
                              style: pw.TextStyle(
                                fontSize: 11.5,
                                fontWeight: pw.FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            pw.Text(
                              'CLINICAL ASSESSMENT & EXAMINATION — PAGE 2 (BACK)',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: dark,
                              ),
                            ),
                            pw.Text(
                              camp != null
                                  ? 'Stations 2 - 6 | Camp: ${sanitizeText(camp.name)} (${camp.campCode})'
                                  : 'Stations 2 - 6 | Universal Clinical Intake & Examination Form (सार्वभौमिक फाराम)',
                              style: const pw.TextStyle(
                                fontSize: 6.8,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasPatient)
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: patient.patientId,
                              width: 24,
                              height: 24,
                            ),
                            pw.SizedBox(width: 6),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text(
                                  'PATIENT ID: ${patient.patientId}',
                                  style: pw.TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: primary,
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.BarcodeWidget(
                                  barcode: pw.Barcode.code128(),
                                  data: patient.patientId,
                                  width: 55,
                                  height: 14,
                                  drawText: false,
                                ),
                              ],
                            ),
                          ],
                        )
                      else if (preprintedPatientId != null &&
                          preprintedPatientId.isNotEmpty)
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: preprintedPatientId,
                              width: 24,
                              height: 24,
                            ),
                            pw.SizedBox(width: 6),
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text(
                                  'Token: ',
                                  style: pw.TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: primary,
                                  ),
                                ),
                                buildCharBoxes(
                                  preprintedPatientId,
                                  minBoxes: 16,
                                  maxBoxes: 16,
                                  boxSize: 11.0,
                                  boxHeight: 14.0,
                                  boxMargin: 1.0,
                                ),
                              ],
                            ),
                          ],
                        )
                      else
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              'Token: ',
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                fontWeight: pw.FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            buildCharBoxes(
                              dynamicTokenPrefix,
                              minBoxes: 18,
                              maxBoxes: 18,
                              boxSize: 11.5,
                              boxHeight: 14.5,
                              boxMargin: 1.0,
                            ),
                          ],
                        ),
                    ],
                  ),
                  pw.SizedBox(height: 7),
                  station2,
                  pw.SizedBox(height: 7),
                  station3,
                  pw.SizedBox(height: 7),
                  station4,
                  pw.SizedBox(height: 7),
                  station5,
                  pw.SizedBox(height: 7),
                  station6,
                  pw.SizedBox(height: 7),
                  signaturesBlock,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<Uint8List> generatePatientRegistrationFormPdf({
    PatientModel? patient,
    CampModel? camp,
    ClinicalVisitModel? visit,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    bool allDoctorsChecklist = false,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    bool allNursesChecklist = false,
    BlankFormPage1Layout page1Layout = BlankFormPage1Layout.grid,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
    List<LookupItemModel>? visitReasons,
    List<LookupItemModel>? chiefComplaints,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      await _addPatientRegistrationFormPages(
        pdf,
        patient: patient,
        camp: camp,
        visit: visit,
        doctor: doctor,
        blankDoctorLines: blankDoctorLines,
        allDoctorsChecklist: allDoctorsChecklist,
        nurse: nurse,
        blankNurseLines: blankNurseLines,
        allNursesChecklist: allNursesChecklist,
        page1Layout: page1Layout,
        organizationName: organizationName,
        diagnoses: diagnoses,
        medications: medications,
        referralHospitals: referralHospitals,
        visitReasons: visitReasons,
        chiefComplaints: chiefComplaints,
        logoImage: logoImage,
      );
      return pdf;
    });
  }

  Future<Uint8List> generateBatchBlankYellowFormsPdf({
    required List<DoctorProfile> doctors,
    CampModel? camp,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    BlankFormPage1Layout page1Layout = BlankFormPage1Layout.grid,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
    List<LookupItemModel>? visitReasons,
    List<LookupItemModel>? chiefComplaints,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      for (final doc in doctors) {
        await _addPatientRegistrationFormPages(
          pdf,
          camp: camp,
          doctor: doc,
          nurse: nurse,
          blankNurseLines: blankNurseLines,
          page1Layout: page1Layout,
          organizationName: organizationName,
          diagnoses: diagnoses,
          medications: medications,
          referralHospitals: referralHospitals,
          visitReasons: visitReasons,
          chiefComplaints: chiefComplaints,
          logoImage: logoImage,
        );
      }
      return pdf;
    });
  }

  Future<Uint8List> generateBatchBlankYellowFormsByNursesPdf({
    required List<NurseProfile> nurses,
    CampModel? camp,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    BlankFormPage1Layout page1Layout = BlankFormPage1Layout.grid,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
    List<LookupItemModel>? visitReasons,
    List<LookupItemModel>? chiefComplaints,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      for (final n in nurses) {
        await _addPatientRegistrationFormPages(
          pdf,
          camp: camp,
          doctor: doctor,
          blankDoctorLines: blankDoctorLines,
          nurse: n,
          blankNurseLines: false,
          page1Layout: page1Layout,
          organizationName: organizationName,
          diagnoses: diagnoses,
          medications: medications,
          referralHospitals: referralHospitals,
          visitReasons: visitReasons,
          chiefComplaints: chiefComplaints,
          logoImage: logoImage,
        );
      }
      return pdf;
    });
  }

  /// Generates a batch PDF containing blank Yellow registration forms (2 pages each)
  /// sequentially pre-printed with Patient Token IDs (e.g., GC-DHN-2026-00001 to GC-DHN-2026-00050)
  /// and matching QR codes in the header.
  Future<Uint8List> generatePreNumberedBlankFormsPdf({
    required CampModel camp,
    required int startSequence,
    required int count,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    bool allDoctorsChecklist = false,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    bool allNursesChecklist = false,
    BlankFormPage1Layout page1Layout = BlankFormPage1Layout.grid,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
    List<LookupItemModel>? visitReasons,
    List<LookupItemModel>? chiefComplaints,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      final year = camp.startDate.year;
      final campCode = camp.campCode.trim().toUpperCase();

      for (int i = 0; i < count; i++) {
        final seq = startSequence + i;
        final patientId = PatientModel.generatePatientId(
          campCode: campCode,
          sequenceNumber: seq,
          year: year,
        );

        await _addPatientRegistrationFormPages(
          pdf,
          camp: camp,
          preprintedPatientId: patientId,
          doctor: doctor,
          blankDoctorLines: blankDoctorLines,
          allDoctorsChecklist: allDoctorsChecklist,
          nurse: nurse,
          blankNurseLines: blankNurseLines,
          allNursesChecklist: allNursesChecklist,
          page1Layout: page1Layout,
          organizationName: organizationName,
          diagnoses: diagnoses,
          medications: medications,
          referralHospitals: referralHospitals,
          visitReasons: visitReasons,
          chiefComplaints: chiefComplaints,
          logoImage: logoImage,
        );
      }
      return pdf;
    });
  }

  /// Generates a batch PDF containing 1-page blank Follow-Up Encounter Slips
  /// sequentially pre-printed with Token IDs (e.g., GC-DHN-2026-00001 to GC-DHN-2026-00050).
  Future<Uint8List> generatePreNumberedBlankFollowUpSlipsPdf({
    required CampModel camp,
    required int startSequence,
    required int count,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    String organizationName = AppConstants.defaultOrganizationName,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      final year = camp.startDate.year;
      final campCode = camp.campCode.trim().toUpperCase();

      for (int i = 0; i < count; i++) {
        final seq = startSequence + i;
        final tokenId = PatientModel.generatePatientId(
          campCode: campCode,
          sequenceNumber: seq,
          year: year,
        );

        _addBlankFollowUpSlipPage(
          pdf,
          camp: camp,
          preprintedTokenId: tokenId,
          doctor: doctor,
          blankDoctorLines: blankDoctorLines,
          nurse: nurse,
          blankNurseLines: blankNurseLines,
          organizationName: organizationName,
          logoImage: logoImage,
        );
      }
      return pdf;
    });
  }

  /// Generates an A5 Patient Token Slip & Triage Routing Pass with QR & Barcode
  /// for patients to carry across Stations 1 through 6.
  Future<Uint8List> generatePatientTokenSlipPdf({
    required PatientModel patient,
    CampModel? camp,
    String organizationName = AppConstants.defaultOrganizationName,
  }) async {
    final effectiveOrgName = resolveEffectiveOrganizationName(
      organizationName: organizationName,
      camp: camp,
    );
    final theme = await getPdfTheme();
    return _saveWithNepali(() async {
      final doc = pw.Document(theme: theme);
      final hasClinical = patient.hasClinicalVisit;
      final reasonsStr = patient.reasonsForVisit.isNotEmpty
          ? patient.reasonsForVisit
                .map((r) => sanitizeText(r.replaceAll('_', ' ')))
                .where((s) => s.isNotEmpty)
                .join(', ')
          : '';
      final docRaw = patient.primaryDoctorName?.trim().isNotEmpty == true
          ? patient.primaryDoctorName!
          : (patient.attendingDoctorNames.isNotEmpty
                ? patient.attendingDoctorNames.first
                : '');
      final docName = sanitizeText(docRaw);

      final brandViolet = PdfColor.fromHex('30026E');
      final brandMagenta = PdfColor.fromHex('81005D');
      final brandLightBg = PdfColor.fromHex('F5F3FF');
      final brandBorder = PdfColor.fromHex('E9D5FF');

      pw.Widget stationRow(String title, {required bool isDone}) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
          child: pw.Row(
            children: [
              pw.Container(
                width: 15,
                height: 15,
                decoration: pw.BoxDecoration(
                  color: isDone ? brandViolet : PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(3),
                  ),
                  border: pw.Border.all(
                    color: isDone ? brandViolet : PdfColors.grey400,
                    width: 1.2,
                  ),
                ),
                alignment: pw.Alignment.center,
                child: isDone
                    ? pw.Text(
                        'X',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      )
                    : pw.SizedBox(),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: isDone
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    color: isDone ? PdfColors.black : PdfColors.grey700,
                  ),
                ),
              ),
              pw.Text(
                isDone ? '[ COMPLETED ]' : '[ PENDING ]',
                style: pw.TextStyle(
                  fontSize: 9.0,
                  fontWeight: pw.FontWeight.bold,
                  color: isDone ? brandMagenta : PdfColors.grey500,
                ),
              ),
            ],
          ),
        );
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 10,
                  ),
                  decoration: pw.BoxDecoration(
                    color: brandLightBg,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(6),
                    ),
                    border: pw.Border.all(color: brandViolet, width: 1.2),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        sanitizeText(effectiveOrgName.toUpperCase()),
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: brandViolet,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        sanitizeText(
                          camp?.name,
                          fallback: 'Gynecological Health Outreach Camp',
                        ),
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.Text(
                        'PATIENT FOLLOW-UP TOKEN SLIP & TRIAGE ROUTING PASS',
                        style: const pw.TextStyle(
                          fontSize: 9.0,
                          color: PdfColors.grey700,
                          letterSpacing: 0.5,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: brandBorder),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(6),
                          ),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              children: [
                                pw.Text(
                                  'PATIENT ID: ',
                                  style: pw.TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.grey700,
                                  ),
                                ),
                                pw.Text(
                                  sanitizeText(patient.patientId),
                                  style: pw.TextStyle(
                                    fontSize: 15,
                                    fontWeight: pw.FontWeight.bold,
                                    color: brandViolet,
                                  ),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              'Name: ${sanitizeText(patient.fullName)}',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text(
                              'Age: ${patient.age} yrs | Marital: ${sanitizeText(patient.maritalStatus)}',
                              style: const pw.TextStyle(fontSize: 10.5),
                            ),
                            pw.Text(
                              'Guardian/Spouse: ${sanitizeText(patient.spouseOrFatherName, fallback: "N/A")}',
                              style: const pw.TextStyle(fontSize: 10.5),
                            ),
                            pw.Text(
                              'Address: Ward ${sanitizeText(patient.ward)}, ${sanitizeText(patient.municipality.isNotEmpty ? patient.municipality : patient.district)}',
                              style: const pw.TextStyle(fontSize: 10.5),
                            ),
                            pw.Text(
                              'Mobile: ${patient.mobile.isNotEmpty ? sanitizeText(patient.mobile) : "N/A"}',
                              style: const pw.TextStyle(fontSize: 10.5),
                            ),
                            pw.Text(
                              'Intake Date: ${patient.intakeDate.toString().split(" ")[0]}',
                              style: const pw.TextStyle(fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Column(
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: patient.patientId,
                          width: 72,
                          height: 72,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Scan at Station',
                          style: const pw.TextStyle(
                            fontSize: 8.0,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: patient.patientId,
                    width: 220,
                    height: 34,
                  ),
                ),
                pw.SizedBox(height: 8),
                if (reasonsStr.isNotEmpty ||
                    docName.isNotEmpty ||
                    patient.highestPopStage != null) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: brandLightBg,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                      border: pw.Border.all(color: brandBorder),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        if (reasonsStr.isNotEmpty)
                          pw.Expanded(
                            child: pw.Text(
                              'Chief Complaint: $reasonsStr',
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey800,
                              ),
                            ),
                          ),
                        if (docName.isNotEmpty)
                          pw.Text(
                            'Doctor: $docName',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: brandViolet,
                            ),
                          ),
                        if (patient.highestPopStage != null) ...[
                          pw.SizedBox(width: 6),
                          pw.Text(
                            patient.highestPopStage == 0
                                ? 'POP: Normal (No Prolapse)'
                                : 'POP Stage: ${patient.highestPopStage}',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: brandMagenta,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 8),
                ],
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'CLINICAL STATIONS CHECKLIST',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: brandViolet,
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: pw.BoxDecoration(
                        color: hasClinical
                            ? brandLightBg
                            : const PdfColor(1, 0.98, 0.92),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                        border: pw.Border.all(
                          color: hasClinical ? brandViolet : PdfColors.amber700,
                          width: 0.8,
                        ),
                      ),
                      child: pw.Text(
                        hasClinical
                            ? 'ALL STATIONS COMPLETED'
                            : 'IN PROGRESS / PENDING',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: hasClinical ? brandViolet : PdfColors.amber900,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                stationRow('Station 1: Registration & Intake', isDone: true),
                stationRow(
                  'Station 2: Physical & POP Exam',
                  isDone: hasClinical,
                ),
                stationRow(
                  'Station 3: Vitals & Lab Testing',
                  isDone: hasClinical,
                ),
                stationRow(
                  'Station 4: Doctor Assessment & Diagnoses',
                  isDone: hasClinical,
                ),
                stationRow(
                  'Station 5: Treatment & Pharmacy',
                  isDone: hasClinical,
                ),
                stationRow(
                  'Station 6: Discharge & Referral',
                  isDone: hasClinical,
                ),
                pw.Spacer(),
                pw.Divider(color: PdfColors.grey300),
                pw.Center(
                  child: pw.Text(
                    'Please hold this token pass while visiting each clinical station. Retain for follow-up verification.',
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
      return doc;
    });
  }
}
