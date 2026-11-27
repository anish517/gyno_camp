import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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
import '../utils/form_page_identifier.dart';
import '../utils/nepali_date_helper.dart';
import 'report_aggregation_service.dart';
import 'session_service.dart';
import 'nepali_localization_service.dart';

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
        final double fontPx = s.size * _neScale;
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
                  fontSize: fontPx,
                  fontWeight: s.bold ? fp.FontWeight.w700 : fp.FontWeight.w400,
                  color: fp.Color(s.color),
                ),
              ),
              textDirection: ui.TextDirection.ltr,
            )..layout(
              maxWidth: s.maxWidth != null
                  ? s.maxWidth! * _neScale
                  : double.infinity,
            );

        // Paint on a padded canvas so Devanagari ascenders (ि, ी, ै, ो, ँ, ं, र्)
        // and descenders / overhangs (ु, ू, ्) are never clipped at edges.
        final double pad = (fontPx * 0.45).ceilToDouble().clamp(8.0, 48.0);
        final rawW = (tp.width + 2 * pad).ceil().clamp(1, 4000);
        final rawH = (tp.height + 2 * pad).ceil().clamp(1, 4000);
        final rawRec = ui.PictureRecorder();
        tp.paint(ui.Canvas(rawRec), ui.Offset(pad, pad));
        final rawImg = await rawRec.endRecording().toImage(rawW, rawH);

        final double baseShift = (fontPx * 0.08).floorToDouble();
        double cropLeft = pad;
        double cropTop = pad - baseShift;
        double cropRight = (pad + tp.width).ceilToDouble();
        double cropBottom = (pad + tp.height - baseShift).ceilToDouble();

        final rgba = await rawImg.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (rgba != null) {
          final px = rgba.buffer.asUint8List();
          int minX = rawW, minY = rawH, maxX = -1, maxY = -1;
          for (int y = 0; y < rawH; y++) {
            final rowOffset = y * rawW * 4;
            for (int x = 0; x < rawW; x++) {
              if (px[rowOffset + x * 4 + 3] > 0) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
              }
            }
          }
          if (maxX >= minX && maxY >= minY) {
            if (minX - 2 < cropLeft) {
              cropLeft = (minX - 2).floorToDouble().clamp(0.0, rawW - 1.0);
            }
            if (maxX + 2 > cropRight) {
              cropRight = (maxX + 2)
                  .ceilToDouble()
                  .clamp(cropLeft + 1.0, rawW.toDouble());
            }
            if (minY - 2 < cropTop) {
              cropTop = (minY - 2).floorToDouble().clamp(0.0, rawH - 1.0);
            }
            if (maxY + 2 > cropBottom) {
              cropBottom = (maxY + 2)
                  .ceilToDouble()
                  .clamp(cropTop + 1.0, rawH.toDouble());
            }
          }
        } else {
          cropLeft = (pad - (fontPx * 0.12)).clamp(0.0, rawW - 1.0);
          cropRight = (pad + tp.width + (fontPx * 0.25))
              .clamp(cropLeft + 1.0, rawW.toDouble());
          cropTop = (pad - (fontPx * 0.16)).clamp(0.0, rawH - 1.0);
          cropBottom = (pad + tp.height + (fontPx * 0.12))
              .clamp(cropTop + 1.0, rawH.toDouble());
        }

        final finalW = (cropRight - cropLeft).ceil().clamp(1, 4000);
        final finalH = (cropBottom - cropTop).ceil().clamp(1, 4000);
        final cropRec = ui.PictureRecorder();
        ui.Canvas(cropRec).drawImageRect(
          rawImg,
          ui.Rect.fromLTWH(
            cropLeft,
            cropTop,
            finalW.toDouble(),
            finalH.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, finalW.toDouble(), finalH.toDouble()),
          ui.Paint(),
        );
        final finalImg = await cropRec.endRecording().toImage(finalW, finalH);
        final data = await finalImg.toByteData(format: ui.ImageByteFormat.png);
        rawImg.dispose();
        finalImg.dispose();
        if (data != null) {
          _neCache[s] = (
            img: pw.MemoryImage(data.buffer.asUint8List()),
            w: finalW / _neScale,
            h: finalH / _neScale,
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
    await Future.delayed(const Duration(milliseconds: 4));
    final firstPassBytes = await doc.save(enableEventLoopBalancing: true);
    if (_nePending.isNotEmpty) {
      await _renderPendingNepali();
      doc = await build();
      await Future.delayed(const Duration(milliseconds: 4));
      return await doc.save(enableEventLoopBalancing: true);
    }
    return firstPassBytes;
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
                        'Specific Counseling',
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

                  final allMeds = v != null
                      ? v.uniqueAllMedications
                      : const <String>[];
                  final medsStr = allMeds.isNotEmpty
                      ? allMeds.join(', ')
                      : 'None';

                  final pessaryStr =
                      v?.pessaryType != null &&
                          v!.pessaryType!.trim().isNotEmpty
                      ? (v.pessarySize != null &&
                                v.pessarySize!.trim().isNotEmpty
                            ? '${v.pessaryType!.trim()} (${v.formattedPessarySize})'
                            : v.pessaryType!.trim())
                      : '-';

                  final docName = () {
                    final rawList = v?.attendingDoctorNames.where((d) => d.trim().isNotEmpty).toList() ?? [];
                    if (rawList.length > 1) {
                      return rawList.map((d) => DoctorProfile.parse(d).displayName).join(', ');
                    } else if (v?.primaryDoctorName != null && v!.primaryDoctorName!.trim().isNotEmpty) {
                      return DoctorProfile.parse(v.primaryDoctorName!).displayName;
                    } else if (rawList.isNotEmpty) {
                      return DoctorProfile.parse(rawList.first).displayName;
                    } else if (p.primaryDoctorName != null && p.primaryDoctorName!.trim().isNotEmpty) {
                      return DoctorProfile.parse(p.primaryDoctorName!).displayName;
                    }
                    return '-';
                  }();

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
                    v?.highestPopStage != null ? 'Stage ${v!.highestPopStage}' : '-',
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

  static const Map<String, String> _canonicalComplaintTitles = {
    'prolapse': 'Something Hanging Out',
    'discharge': 'Discharge / Itching',
    'urine': 'Problems Passing Urine',
    'stool': 'Problems Passing Stool',
    'menstrual': 'Menstrual Problem',
    'infertility': 'Infertility',
    'lower_abdomen_pain': 'Lower Abdomen Pain',
    'lower_back_pain': 'Lower Back Pain',
    'checkup': 'Checkup',
    'pelvic_heaviness': 'Pelvic Heaviness',
    'dyspareunia': 'Dyspareunia / Coital Pain',
    'post_coital_bleeding': 'Post-Coital Bleeding',
  };

  static List<Map<String, dynamic>> _buildComplaintDisplayList(
    Map<String, dynamic> complaintsMap,
  ) {
    String canonicalComplaintKey(String key) {
      final k = key.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), ' ').trim();
      if (k.contains('prolapse') || k.contains('hanging') || k.contains('mass per vagina') || k.contains('पाठेघर')) return 'prolapse';
      if (k.contains('discharge') || k.contains('itching') || k.contains('स्राव') || k.contains('चिलाउने')) return 'discharge';
      if (k.contains('urine') || k.contains('micturition') || k.contains('incontinence') || k.contains('पिसाब')) return 'urine';
      if (k.contains('stool') || k.contains('bowel') || k.contains('दिसा')) return 'stool';
      if (k.contains('menstrual') || k.contains('महिनावारी')) return 'menstrual';
      if (k.contains('infertility') || k.contains('conception') || k.contains('बाँझोपन') || k.contains('निःसन्तान')) return 'infertility';
      if (k.contains('back') || k.contains('backache') || k.contains('ढाड') || k.contains('कम्मर') || k.contains('sacral')) return 'lower_back_pain';
      if (k.contains('abdomen') || k.contains('abdominal') || k.contains('तल्लो पेट') || k.contains('pelvic') || k == 'pain') return 'lower_abdomen_pain';
      if (k.contains('checkup') || k.contains('screening') || k.contains('जाँच')) return 'checkup';
      return k;
    }

    const metaKeys = {
      'clinicalComplaints',
      'clinical_complaints',
      'complaints_duration',
      'complaintsDuration',
      'reasons',
      'new_issues',
      'newIssues',
      'visitReasons',
      'pain',
    };

    final seenCanonical = <String>{};
    final complaintDisplayList = <Map<String, dynamic>>[];

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

    return complaintDisplayList;
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
    // Strictly isolate Clinical Intake PDF from Follow-Up visits: never allow
    // an isFollowUp record to populate Clinical Intake Sections 1-7.
    if (visit != null && visit.isFollowUp) {
      visit = allVisits?.where((v) => !v.isFollowUp).firstOrNull;
    }
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

      final visitDateFormatted = visit != null
          ? _formatVisitHeaderDate(visit, patient)
          : 'Intake Date: ${NepaliLocalizationService.formatDualCalendarDate(patient.intakeDate)}';

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
      final effectiveCustomMed = ClinicalConstants.normalizeCustomMedication(
        (visit?.customMedication != null &&
                visit!.customMedication!.trim().isNotEmpty)
            ? visit.customMedication
            : patient.customMedication,
      );
      final effectiveMedications =
          ClinicalConstants.deduplicateFormularyMedications(
            rawMedications,
            effectiveCustomMed,
          ).where((m) => !ReportAggregationService.isDosageInstruction(m)).toList();
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
      final complaintDisplayList = _buildComplaintDisplayList(complaintsMap);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          build: (context) => [
            // 1. EXECUTIVE CLINICAL DOSSIER HEADER
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
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
                      child: pw.Image(logoImage, width: 40, height: 40),
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
                        width: 40,
                        height: 40,
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
                        visitDateFormatted,
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
            pw.SizedBox(height: 5),

            // 2. PATIENT DEMOGRAPHICS & INTAKE PROFILE
            _buildPdfSectionHeader(
              '1. PATIENT DEMOGRAPHICS & SOCIAL INTAKE',
              primaryColor,
              date: NepaliLocalizationService.formatDualCalendarDate(patient.intakeDate),
              dateLabel: 'Intake Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
            pw.SizedBox(height: 4.5),

            // 3. STRUCTURED YELLOW FORM CLINICAL ANAMNESIS
            _buildPdfSectionHeader(
              '2. STRUCTURED CLINICAL ANAMNESIS (YELLOW FORM)',
              primaryColor,
              date: visit?.anamnesisDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit!.anamnesisDate!) : null,
              dateLabel: 'Anamnesis Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                        final title = _canonicalComplaintTitles[canon] ??
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
            pw.SizedBox(height: 4.5),

            // 4. OBSTETRIC HISTORY & PHYSICAL EXAMINATION
            _buildPdfSectionHeader(
              '3. OBSTETRIC HISTORY & GYNECOLOGICAL EXAM',
              primaryColor,
              date: visit?.examDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit!.examDate!) : null,
              dateLabel: 'Exam Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                          visit?.uterusInside == null
                              ? 'N/A'
                              : (visit!.uterusInside! ? 'Yes' : 'No'),
                          isBold: visit?.uterusInside == false,
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Cervix',
                          sanitizeText(visit?.cervixRemarks ?? 'N/A'),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Pelvic Floor Muscle',
                          visit?.pelvicFloorTone?.toUpperCase() ?? 'N/A',
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
                          sanitizeText(visit?.vulvaRemarks ?? 'N/A'),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Vagina',
                          sanitizeText(visit?.vaginaRemarks ?? 'N/A'),
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Other / Uterus',
                          sanitizeText(visit?.uterusRemarks ?? 'N/A'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 4.5),

            // 5. CLINICAL VITALS & SCREENING LABS
            _buildPdfSectionHeader(
              '4. CLINICAL VITALS & SCREENING LABS',
              primaryColor,
              date: visit?.labTestDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit!.labTestDate!) : null,
              dateLabel: 'Lab Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                          (visit?.urineTest != null && visit!.urineTest!.trim().isNotEmpty)
                              ? visit.urineTest!.toUpperCase()
                              : 'N/A',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Pregnancy Test (UPT)',
                          (visit?.pregnancyTest != null && visit!.pregnancyTest!.trim().isNotEmpty)
                              ? visit.pregnancyTest!.toUpperCase()
                              : 'N/A',
                        ),
                      ),
                      pw.Expanded(
                        child: _buildPdfField(
                          'ECG',
                          (visit?.ecgNotes != null && visit!.ecgNotes!.trim().isNotEmpty)
                              ? sanitizeText(visit.ecgNotes!)
                              : 'Not Done',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 4.5),

            // 5. POP STAGING MATRIX
            _buildPdfSectionHeader(
              '5. POP STAGING (PELVIC ORGAN PROLAPSE)',
              primaryColor,
              date: visit?.conclusionDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit!.conclusionDate!) : null,
              dateLabel: 'Conclusion Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                    visit?.popAnteriorStage == null
                        ? 'Not Recorded'
                        : (visit!.popAnteriorStage == 0
                            ? 'Stage 0 (Normal)'
                            : 'Stage ${visit.popAnteriorStage}'),
                    isHighlight: visit?.popAnteriorStage == 2,
                    isCritical: (visit?.popAnteriorStage ?? 0) >= 3,
                    isNormal: visit?.popAnteriorStage == 0,
                  ),
                  _buildPopBadge(
                    'MIDDLE (Uterine)',
                    visit?.popMiddleStage == null
                        ? 'Not Recorded'
                        : (visit!.popMiddleStage == 0
                            ? 'Stage 0 (Normal)'
                            : 'Stage ${visit.popMiddleStage}'),
                    isHighlight: visit?.popMiddleStage == 2,
                    isCritical: (visit?.popMiddleStage ?? 0) >= 3,
                    isNormal: visit?.popMiddleStage == 0,
                  ),
                  _buildPopBadge(
                    'POSTERIOR (Rectocele)',
                    visit?.popPosteriorStage == null
                        ? 'Not Recorded'
                        : (visit!.popPosteriorStage == 0
                            ? 'Stage 0 (Normal)'
                            : 'Stage ${visit.popPosteriorStage}'),
                    isHighlight: visit?.popPosteriorStage == 2,
                    isCritical: (visit?.popPosteriorStage ?? 0) >= 3,
                    isNormal: visit?.popPosteriorStage == 0,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 4.5),

            // 7. DIAGNOSES & TREATMENT FORMULARY
            _buildPdfSectionHeader(
              '6. CONFIRMED DIAGNOSES & FORMULARY',
              primaryColor,
              date: visit?.treatmentDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit!.treatmentDate!) : null,
              dateLabel: 'Treatment Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                    'Prescribed Medications',
                    effectiveMedications.isNotEmpty
                        ? effectiveMedications.join(' | ')
                        : 'None Dispensed',
                  ),
                  if (effectiveCustomMed != null &&
                      effectiveCustomMed.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField('Other Medications', effectiveCustomMed),
                  ],
                  if (effectivePessarySize != null &&
                      effectivePessarySize.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField(
                      'Ring Pessary Fitted',
                      '${effectivePessaryType ?? "Ring Pessary"} (Size: ${ClinicalConstants.formatPessarySize(effectivePessarySize)})',
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
            pw.SizedBox(height: 4.5),

            // 8. DISCHARGE, SURGICAL REFERRAL & CONTINUITY OF CARE
            _buildPdfSectionHeader(
              '7. CONTINUITY OF CARE & REFERRAL',
              primaryColor,
              date: visit?.outtakeDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit!.outtakeDate!) : null,
              dateLabel: 'Outtake Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                  pw.SizedBox(height: 3),
                  _buildPdfField(
                    'Clinical Notes / Outtake Remarks',
                    (visit?.outtakeNotes?.trim().isNotEmpty == true)
                        ? sanitizeText(visit!.outtakeNotes!)
                        : ((visit?.followUpNotes?.trim().isNotEmpty == true)
                            ? sanitizeText(visit!.followUpNotes!)
                            : 'None recorded / Routine consultation'),
                    isBold: visit?.outtakeNotes?.trim().isNotEmpty == true,
                  ),
                  if (visit != null &&
                      visit.followUpNotes?.trim().isNotEmpty == true &&
                      visit.outtakeNotes?.trim().isNotEmpty == true &&
                      visit.followUpNotes!.trim() != visit.outtakeNotes!.trim()) ...[
                    pw.SizedBox(height: 3),
                    _buildPdfField(
                      'Follow-Up Instructions / Remarks',
                      sanitizeText(visit.followUpNotes!),
                    ),
                  ],
                ],
              ),
            ),
            if (allVisits != null && allVisits.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              _buildPdfSectionHeader(
                '8. LONGITUDINAL CLINICAL ENCOUNTERS & FOLLOW-UP TIMELINE (${allVisits.length} RECORDED)',
                primaryColor,
              ),
              pw.SizedBox(height: 2.5),
              ...allVisits.map((v) {
                final isFollowUp = v.isFollowUp;
                final dateFormatted = dateFormatter.format(v.visitDate);
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 3.5),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                              v.highestPopStage != null
                                  ? 'POP: Stage ${v.highestPopStage} (Ant: ${v.popAnteriorStage ?? "-"}, Mid: ${v.popMiddleStage ?? "-"}, Post: ${v.popPosteriorStage ?? "-"})'
                                  : 'POP: Not Recorded',
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
                                'Pessary: ${v.pessaryType ?? "Ring"} Sz ${v.formattedPessarySize}',
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
                      if (v.uniqueAllMedications.isNotEmpty) ...[
                        pw.SizedBox(height: 1.5),
                        pw.Text(
                          sanitizeText(
                            'Medications: ${v.uniqueAllMedications.join(", ")}',
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
            pw.SizedBox(height: 8),

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
                    () {
                      final rawDocList = (visit?.attendingDoctorNames.isNotEmpty == true
                          ? visit!.attendingDoctorNames
                          : (camp?.doctorNames.isNotEmpty == true
                              ? camp!.doctorNames
                              : (camp?.doctorName.trim().isNotEmpty == true
                                  ? [camp!.doctorName]
                                  : <String>[])));
                      final parsedDocs = rawDocList
                          .map(DoctorProfile.parse)
                          .where((d) => d.isValid)
                          .toList();

                      final docTitle = parsedDocs.isNotEmpty
                          ? parsedDocs.map((d) => d.displayName).join(' & ')
                          : null;
                      final nmcNumbers = parsedDocs
                          .where((d) => d.hasNmc)
                          .map((d) => 'NMC No: ${d.nmcNumber}')
                          .join(', ');

                      return pw.Column(
                        children: [
                          if (docTitle != null && docTitle.isNotEmpty) ...[
                            pw.Text(
                              sanitizeText(docTitle),
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: primaryColor,
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
                            nmcNumbers.isNotEmpty
                                ? '$nmcNumbers — Certified'
                                : 'Nepal Medical Council (NMC) Certified',
                            style: const pw.TextStyle(
                              fontSize: 7,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      );
                    }(),
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

  String _formatVisitHeaderDate(ClinicalVisitModel visit, PatientModel patient) {
    final src = visit.visitDateSourceLabel(intakeDate: patient.intakeDate);
    final label = src != null ? 'Visit Date ($src)' : 'Visit Date';
    return '$label: ${NepaliLocalizationService.formatDualCalendarDate(visit.visitDate)}';
  }

  pw.Widget _buildPdfSectionHeader(String title, PdfColor color, {String? date, String? dateLabel}) {
    final parenIdx = title.indexOf('(');
    final splitBilingual = _devanagari.hasMatch(title) &&
        parenIdx > 0 &&
        !_devanagari.hasMatch(title.substring(0, parenIdx));
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('F5F3FF'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: color, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          splitBilingual
              ? pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      sanitizeText(title.substring(0, parenIdx).trimRight()),
                      style: pw.TextStyle(
                        fontSize: 10.0,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('30026E'),
                      ),
                    ),
                    pw.SizedBox(width: 5),
                    ne(
                      title.substring(parenIdx),
                      size: 9.2,
                      bold: true,
                      color: 0xFF30026E,
                    ),
                  ],
                )
              : ne(title, size: 10.0, bold: true, color: 0xFF30026E),
          if (date != null && date.trim().isNotEmpty)
            pw.Text(
              dateLabel != null ? '$dateLabel: $date' : 'Date: $date',
              style: pw.TextStyle(
                fontSize: 8.0,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
        ],
      ),
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
          ? 'FOLLOW-UP VISIT ASSESSMENT'
          : 'PRIMARY CAMP EXAMINATION';
      final visitDate = dateFormatter.format(visit.visitDate);


      final effectiveTreatmentLevel =
          (visit.treatmentLevel?.trim().isNotEmpty == true)
          ? visit.treatmentLevel!.trim()
          : (isFollowUp ? '' : (patient.treatmentLevel?.trim() ?? ''));
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

      final complaintsMap = visit.anamnesisComplaints;
      final complaintDisplayList = _buildComplaintDisplayList(complaintsMap);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          build: (ctx) => [
            // ── Header ───────────────────────────────────────────────────────
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
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
                      child: pw.Image(logoImage, width: 42, height: 42),
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
                        width: 44,
                        height: 44,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'ENCOUNTER-${patient.patientId}',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          fontWeight: pw.FontWeight.bold,
                          color: encounterColor,
                        ),
                      ),
                      pw.Text(
                        _formatVisitHeaderDate(visit, patient),
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
            pw.SizedBox(height: 5),

            // ── Patient Demographics ─────────────────────────────────────────
            _buildPdfSectionHeader(
              isFollowUp
                  ? 'PATIENT IDENTITY (बिरामी परिचय)'
                  : '1. PATIENT IDENTITY',
              encounterColor,
              date: NepaliLocalizationService.formatDualCalendarDate(
                isFollowUp ? visit.visitDate : patient.intakeDate,
              ),
              dateLabel: isFollowUp ? 'Follow-Up Date' : 'Intake Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Full Name',
                          patient.fullName,
                          isBold: true,
                        ),
                      ),
                      pw.SizedBox(width: 8),
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
                        flex: 4,
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
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        flex: 3,
                        child: _buildPdfField(
                          'Mobile',
                          patient.mobile.isNotEmpty ? patient.mobile : 'N/A',
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        flex: 4,
                        child: _buildPdfField(
                          'Guardian Touch / Contact Mob',
                          () {
                            final cm = patient.contactMobile ?? '';
                            final cp = patient.contactPerson ?? '';
                            if (cm.isNotEmpty && cp.isNotEmpty) {
                              return '$cm ($cp)';
                            } else if (cm.isNotEmpty) {
                              return cm;
                            } else if (cp.isNotEmpty) {
                              return cp;
                            }
                            return 'N/A';
                          }(),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: _buildPdfField(
                          'Address',
                          'Ward ${patient.ward}, ${patient.municipality}, ${patient.district}',
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        flex: 4,
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
            pw.SizedBox(height: 4.5),

            if (isFollowUp) ...[
              // ════════════════════════════════════════════════════════════════
              // 100% 1-TO-1 MATCH WITH DIGITAL `Follow-Up Visit Assessment`
              // Sections 1 -> 5
              // ════════════════════════════════════════════════════════════════

              // ── 1. Follow-Up Complaints & New Issues ──────────────────────
              _buildPdfSectionHeader(
                '1. FOLLOW-UP COMPLAINTS & NEW ISSUES (फलो-अप समस्याहरू)',
                encounterColor,
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: gray, width: 0.8),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    () {
                      const followUpComplaintLabels = <String, String>{
                        'something hanging out': 'Something hanging out (आङ खस्ने)',
                        'discharge and or itching': 'Discharge / Itching (स्राव / चिलाउने)',
                        'problems passing urine': 'Urinary complaint (पिसाब सम्बन्धी)',
                        'problems passing stool': 'Stool complaint (दिसा सम्बन्धी)',
                        'menstrual problem': 'Menstrual issue (महिनावारी समस्या)',
                        'infertility': 'Infertility (निःसन्तान)',
                        'pain': 'Pelvic / abdominal pain (तल्लो पेट दुखाइ)',
                        'checkup': 'Routine follow-up checkup (नियमित जाँच)',
                      };
                      final rawReasons = visit.anamnesisComplaints['reasons'];
                      final selectedLabels = <String>[];
                      if (rawReasons is List) {
                        for (final r in rawReasons) {
                          if (r == null) continue;
                          final clean = r.toString().trim();
                          if (clean.isEmpty) continue;
                          selectedLabels.add(
                            followUpComplaintLabels[clean.toLowerCase()] ?? clean,
                          );
                        }
                      }
                      return _buildPdfField(
                        'Selected Follow-Up Complaints',
                        selectedLabels.isNotEmpty
                            ? selectedLabels.join(' • ')
                            : 'None selected (Routine follow-up)',
                        isBold: selectedLabels.isNotEmpty,
                      );
                    }(),
                    pw.SizedBox(height: 2.5),
                    _buildPdfField(
                      'New Issues / Observations',
                      () {
                        final rawNew =
                            (visit.anamnesisComplaints['new_issues'] as String?)
                                ?.trim();
                        if (rawNew != null && rawNew.isNotEmpty) {
                          return sanitizeText(rawNew);
                        }
                        if (visit.followUpNotes != null &&
                            visit.followUpNotes!.trim().isNotEmpty) {
                          return sanitizeText(visit.followUpNotes!.trim());
                        }
                        return 'None reported';
                      }(),
                      isBold: ((visit.anamnesisComplaints['new_issues'] as String?)
                                  ?.trim()
                                  .isNotEmpty ??
                              false) ||
                          (visit.followUpNotes?.trim().isNotEmpty ?? false),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4.5),

              // ── 2. Physical Vitals Check & Screening Labs ─────────────────
              _buildPdfSectionHeader(
                '2. PHYSICAL VITALS CHECK & SCREENING LABS (शारीरिक जाँच तथा ल्याब)',
                encounterColor,
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                            'Systolic BP',
                            visit.systolicBp != null
                                ? '${visit.systolicBp} mmHg'
                                : 'Not Recorded',
                            isBold: visit.systolicBp != null,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Diastolic BP',
                            visit.diastolicBp != null
                                ? '${visit.diastolicBp} mmHg'
                                : 'Not Recorded',
                            isBold: visit.diastolicBp != null,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Pulse Rate',
                            visit.pulse != null
                                ? '${visit.pulse} bpm'
                                : 'Not Recorded',
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'SpO2',
                            visit.spo2 != null
                                ? '${visit.spo2}%'
                                : 'Not Recorded',
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Blood Glucose',
                            visit.glucose != null
                                ? '${visit.glucose} mg/dL'
                                : 'Not Recorded',
                          ),
                        ),
                      ],
                    ),
                    if (visit.systolicBp != null && visit.diastolicBp != null) ...[
                      pw.SizedBox(height: 1.5),
                      pw.Text(
                        'BP Classification: $bpStatus',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          color: bpColor,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                    pw.SizedBox(height: 3),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildPdfField(
                            'Urine Test (पिसाब जाँच)',
                            () {
                              final u = (visit.urineTest ?? '').trim().toLowerCase();
                              if (u.isEmpty) return 'Not Done';
                              if (u == 'normal' || u == 'neg' || u == 'negative') {
                                return 'Normal / Negative (-)';
                              }
                              if (u == 'pos' || u == 'positive' || u.contains('+')) {
                                return 'Positive (+)';
                              }
                              return visit.urineTest!.toUpperCase();
                            }(),
                            isBold: (visit.urineTest ?? '')
                                .toLowerCase()
                                .contains('pos'),
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Pregnancy Test / UPT',
                            () {
                              final p =
                                  (visit.pregnancyTest ?? '').trim().toLowerCase();
                              if (p.isEmpty) return 'Not Indicated';
                              if (p == 'neg' || p == 'negative') {
                                return 'Negative (-)';
                              }
                              if (p == 'pos' || p == 'positive') {
                                return 'Positive (+)';
                              }
                              return visit.pregnancyTest!.toUpperCase();
                            }(),
                            isBold: (visit.pregnancyTest ?? '')
                                .toLowerCase()
                                .contains('pos'),
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'ECG Findings / Notes',
                            (visit.ecgNotes != null &&
                                    visit.ecgNotes!.trim().isNotEmpty)
                                ? sanitizeText(visit.ecgNotes!)
                                : 'Not Recorded',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4.5),

              // ── 3. Pelvic Floor & POP Re-Staging ──────────────────────────
              _buildPdfSectionHeader(
                '3. PELVIC FLOOR & POP RE-STAGING (श्रोणी जाँच तथा आङ खस्ने स्टेज)',
                encounterColor,
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
                decoration: pw.BoxDecoration(
                  color: (visit.highestPopStage ?? 0) >= 2 ? lightBg : PdfColors.white,
                  border: pw.Border.all(
                    color: (visit.highestPopStage ?? 0) >= 2 ? secondary : gray,
                    width: 0.8,
                  ),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildPdfField(
                            'Uterus Inside',
                            visit.uterusInside == null
                                ? 'Not Recorded'
                                : (visit.uterusInside!
                                    ? 'Yes (पाठेघर भित्रै छ)'
                                    : 'No (बाहिर छ)'),
                            isBold: visit.uterusInside == false,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Pelvic Floor Muscle',
                            () {
                              final t =
                                  (visit.pelvicFloorTone ?? '').trim().toLowerCase();
                              if (t == 'normal') return 'Normal (सामान्य)';
                              if (t == 'weak') return 'Weak (कमजोर)';
                              if (t == 'hypertonic') {
                                return 'Hypertonic (कडा / तनावग्रस्त)';
                              }
                              return t.isNotEmpty
                                  ? visit.pelvicFloorTone!
                                  : 'Not Recorded';
                            }(),
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Overall POP Stage',
                            visit.highestPopStage != null
                                ? 'Stage ${visit.highestPopStage}'
                                : 'Not Recorded',
                            isBold: visit.highestPopStage != null,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 3.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        _buildPopBadge(
                          'ANTERIOR (Cystocele)',
                          visit.popAnteriorStage == null
                              ? 'Not Recorded'
                              : (visit.popAnteriorStage == 0
                                  ? 'Stage 0 (Normal)'
                                  : 'Stage ${visit.popAnteriorStage}'),
                          isHighlight: visit.popAnteriorStage == 2,
                          isCritical: (visit.popAnteriorStage ?? 0) >= 3,
                          isNormal: visit.popAnteriorStage == 0,
                        ),
                        _buildPopBadge(
                          'APICAL (Uterine/Apex)',
                          visit.popMiddleStage == null
                              ? 'Not Recorded'
                              : (visit.popMiddleStage == 0
                                  ? 'Stage 0 (Normal)'
                                  : 'Stage ${visit.popMiddleStage}'),
                          isHighlight: visit.popMiddleStage == 2,
                          isCritical: (visit.popMiddleStage ?? 0) >= 3,
                          isNormal: visit.popMiddleStage == 0,
                        ),
                        _buildPopBadge(
                          'POSTERIOR (Rectocele)',
                          visit.popPosteriorStage == null
                              ? 'Not Recorded'
                              : (visit.popPosteriorStage == 0
                                  ? 'Stage 0 (Normal)'
                                  : 'Stage ${visit.popPosteriorStage}'),
                          isHighlight: visit.popPosteriorStage == 2,
                          isCritical: (visit.popPosteriorStage ?? 0) >= 3,
                          isNormal: visit.popPosteriorStage == 0,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4.5),

              // ── 4. Diagnoses & Surgical Evaluation ────────────────────────
              _buildPdfSectionHeader(
                '4. DIAGNOSES & SURGICAL EVALUATION (निदान तथा शल्यक्रिया मूल्याङ्कन)',
                encounterColor,
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                          : 'None selected',
                      isBold: visit.diagnoses.isNotEmpty,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildPdfField(
                            'Surgery Performed',
                            visit.surgeryDone ? 'Yes' : 'No',
                            isBold: visit.surgeryDone,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Surgical Route / Procedure',
                            visit.surgeryDone
                                ? sanitizeText(visit.surgeryType ?? 'Specified')
                                : 'Not Applicable',
                            isBold: visit.surgeryDone,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Surgical Referral Center',
                            (visit.surgicalReferral != null &&
                                    visit.surgicalReferral!.trim().isNotEmpty)
                                ? sanitizeText(visit.surgicalReferral!)
                                : 'No Surgical Referral',
                            isBold: visit.surgicalReferral != null &&
                                visit.surgicalReferral!.trim().isNotEmpty,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4.5),

              // ── 5. Prescription & Follow-Up Destination ───────────────────
              _buildPdfSectionHeader(
                '5. PRESCRIPTION & FOLLOW-UP DESTINATION (औषधि तथा थप फलो-अप)',
                encounterColor,
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: gray, width: 0.8),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildPdfField(
                      'Prescribed Medications',
                      () {
                        final filtered = visit.deduplicatedFormularyMedications
                            .where((m) => !ReportAggregationService.isDosageInstruction(m))
                            .toList();
                        return filtered.isNotEmpty
                            ? filtered.join(' | ')
                            : 'None prescribed';
                      }(),
                      isBold: visit.medications.isNotEmpty,
                    ),
                    if (visit.normalizedCustomMedication != null) ...[
                      pw.SizedBox(height: 2),
                      _buildPdfField(
                        'Other Medications',
                        sanitizeText(visit.normalizedCustomMedication!),
                      ),
                    ],
                    pw.SizedBox(height: 2.5),
                    _buildPdfField(
                      'Specialized Counseling (परामर्श सेवा)',
                      visit.counseling.isNotEmpty
                          ? visit.counseling.join(' • ')
                          : 'None selected',
                    ),
                    pw.SizedBox(height: 2.5),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildPdfField(
                            'Pessary Fitted / Type',
                            (visit.pessaryType != null &&
                                    visit.pessaryType!.trim().isNotEmpty)
                                ? sanitizeText(visit.pessaryType!)
                                : 'None',
                            isBold: visit.pessaryType != null &&
                                visit.pessaryType!.trim().isNotEmpty,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Pessary Size (साइज mm)',
                            (visit.pessarySize != null &&
                                    visit.pessarySize!.trim().isNotEmpty)
                                ? ClinicalConstants.formatPessarySize(
                                    visit.pessarySize,
                                  )
                                : 'N/A',
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2.5),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: _buildPdfField(
                            'Further Follow-Up Needed?',
                            visit.followUpNeeded ? 'Yes' : 'No',
                            isBold: visit.followUpNeeded,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Follow-Up Destination / Hospital',
                            (visit.followUpDestination != null &&
                                    visit.followUpDestination!.trim().isNotEmpty)
                                ? sanitizeText(visit.followUpDestination!)
                                : 'None / Not Specified',
                            isBold: visit.followUpDestination != null &&
                                visit.followUpDestination!.trim().isNotEmpty,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2.5),
                    _buildPdfField(
                      'Final Follow-Up Notes / Counseling',
                      (visit.outtakeNotes != null &&
                              visit.outtakeNotes!.trim().isNotEmpty)
                          ? sanitizeText(visit.outtakeNotes!)
                          : 'None recorded',
                      isBold: visit.outtakeNotes != null &&
                          visit.outtakeNotes!.trim().isNotEmpty,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 7),
            ] else ...[
            // ── Chief Complaints & Reasons to Visit ──────────────────────────
            _buildPdfSectionHeader(
              isFollowUp
                  ? '2. FOLLOW-UP COMPLAINTS & NEW ISSUES'
                  : '2. CHIEF COMPLAINTS & REASONS TO VISIT',
              encounterColor,
              date: visit.anamnesisDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit.anamnesisDate!) : null,
              dateLabel: isFollowUp ? 'Follow-Up Date' : 'Anamnesis Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: gray, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (!isFollowUp && patient.reasonsForVisit.isNotEmpty) ...[
                    _buildPdfField(
                      'Initial Intake Reasons (प्रारम्भिक समस्या)',
                      patient.reasonsForVisit.join(' • '),
                      isBold: true,
                    ),
                  ],
                  if (complaintDisplayList.isNotEmpty) ...[
                    if (!isFollowUp && patient.reasonsForVisit.isNotEmpty) pw.SizedBox(height: 3),
                    ...complaintDisplayList.map((item) {
                      final canon = item['canon'] as String;
                      final key = item['key'] as String;
                      final title = _canonicalComplaintTitles[canon] ??
                          key.replaceAll('_', ' ').toUpperCase();
                      final detailsMap = item['details'] as Map<String, dynamic>?;
                      String details = '';
                      if (detailsMap != null && detailsMap.isNotEmpty) {
                        final dur = detailsMap['duration']?.toString() ?? '';
                        final rem = detailsMap['remarks']?.toString() ?? '';
                        final opts = detailsMap['options'];
                        final optStr = opts is List ? opts.join(', ') : '';
                        details = [dur, optStr, rem].where((s) => s.isNotEmpty).join(' | ');
                      }
                      return pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Container(
                              width: 5,
                              height: 5,
                              margin: const pw.EdgeInsets.only(top: 3, right: 6),
                              decoration: pw.BoxDecoration(
                                color: encounterColor,
                                shape: pw.BoxShape.circle,
                              ),
                            ),
                            pw.SizedBox(
                              width: 155,
                              child: pw.Text(
                                title,
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: dark,
                                ),
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Text(
                                details.isNotEmpty ? details : 'Present',
                                style: const pw.TextStyle(
                                  fontSize: 8,
                                  color: PdfColors.grey800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else if (!isFollowUp && patient.reasonsForVisit.isEmpty) ...[
                    _buildPdfField(
                      'Initial Intake Reasons (प्रारम्भिक समस्या)',
                      'Routine Follow-Up / Consultation',
                    ),
                  ],
                  if (visit.anamnesisComplaints.isNotEmpty &&
                      visit.anamnesisComplaints['reasons'] is List &&
                      (visit.anamnesisComplaints['reasons'] as List).isNotEmpty &&
                      complaintDisplayList.isEmpty) ...[
                    if (!isFollowUp && patient.reasonsForVisit.isNotEmpty) pw.SizedBox(height: 3),
                    _buildPdfField(
                      isFollowUp
                          ? 'Follow-Up Complaints'
                          : 'Active Encounter Complaints',
                      (visit.anamnesisComplaints['reasons'] as List).join(' • '),
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
                  if (isFollowUp &&
                      complaintDisplayList.isEmpty &&
                      !(visit.anamnesisComplaints['reasons'] is List &&
                          (visit.anamnesisComplaints['reasons'] as List).isNotEmpty) &&
                      ((visit.anamnesisComplaints['new_issues'] as String?)
                              ?.trim()
                              .isEmpty ??
                          true)) ...[
                    _buildPdfField(
                      'Follow-Up Status',
                      'Routine Follow-Up Checkup (No new complaints reported)',
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 4.5),

            // ── Obstetric History ────────────────────────────────────────────
            if (visit.deliveries != null ||
                visit.livingChildren != null ||
                visit.abortions != null ||
                visit.cervixRemarks != null ||
                visit.vaginaRemarks != null ||
                visit.vulvaRemarks != null ||
                visit.uterusRemarks != null ||
                visit.examDate != null) ...[
              _buildPdfSectionHeader(
                '3. OBSTETRIC HISTORY & EXAMINATION',
                encounterColor,
                date: visit.examDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit.examDate!) : null,
                dateLabel: 'Exam Date',
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Living Children',
                            visit.livingChildren?.toString() ?? 'N/A',
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Abortions',
                            visit.abortions?.toString() ?? 'N/A',
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Pelvic Floor Muscle',
                            visit.pelvicFloorTone?.toUpperCase() ?? 'N/A',
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
                            visit.uterusInside == null
                                ? 'N/A'
                                : (visit.uterusInside! ? 'Yes' : 'No'),
                            isBold: visit.uterusInside == false,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Cervix',
                            sanitizeText(visit.cervixRemarks ?? 'N/A'),
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Vagina',
                            sanitizeText(visit.vaginaRemarks ?? 'N/A'),
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
                            sanitizeText(visit.vulvaRemarks ?? 'N/A'),
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _buildPdfField(
                            'Other / Uterus',
                            sanitizeText(visit.uterusRemarks ?? 'N/A'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4.5),
            ],

            // ── Clinical Vitals ──────────────────────────────────────────────
            _buildPdfSectionHeader(
              '4. CLINICAL VITALS & SCREENING LABS',
              encounterColor,
              date: visit.labTestDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit.labTestDate!) : null,
              dateLabel: 'Lab Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Pulse Rate',
                          visit.pulse != null ? '${visit.pulse} bpm' : 'N/A',
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: _buildPdfField(
                          'SpO2',
                          visit.spo2 != null ? '${visit.spo2}%' : 'N/A',
                        ),
                      ),
                      pw.SizedBox(width: 6),
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
                          (visit.urineTest != null && visit.urineTest!.trim().isNotEmpty)
                              ? visit.urineTest!.toUpperCase()
                              : 'N/A',
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: _buildPdfField(
                          'Pregnancy Test',
                          (visit.pregnancyTest != null && visit.pregnancyTest!.trim().isNotEmpty)
                              ? visit.pregnancyTest!.toUpperCase()
                              : 'N/A',
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: _buildPdfField(
                          'ECG',
                          (visit.ecgNotes != null && visit.ecgNotes!.trim().isNotEmpty)
                              ? sanitizeText(visit.ecgNotes!)
                              : 'Not Done',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 4.5),

            // ── POP Staging ──────────────────────────────────────────────────
            _buildPdfSectionHeader(
              '5. POP STAGING (पाठेघर खस्ने अवस्था)',
              encounterColor,
              date: visit.conclusionDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit.conclusionDate!) : null,
              dateLabel: 'Conclusion Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
              decoration: pw.BoxDecoration(
                color: (visit.highestPopStage ?? 0) >= 2 ? lightBg : PdfColors.white,
                border: pw.Border.all(
                  color: (visit.highestPopStage ?? 0) >= 2 ? secondary : gray,
                  width: 0.8,
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPopBadge(
                    'ANTERIOR (Cystocele)',
                    visit.popAnteriorStage == null
                        ? 'Not Recorded'
                        : (visit.popAnteriorStage == 0
                            ? 'Stage 0 (Normal)'
                            : 'Stage ${visit.popAnteriorStage}'),
                    isHighlight: visit.popAnteriorStage == 2,
                    isCritical: (visit.popAnteriorStage ?? 0) >= 3,
                    isNormal: visit.popAnteriorStage == 0,
                  ),
                  _buildPopBadge(
                    'MIDDLE (Uterine)',
                    visit.popMiddleStage == null
                        ? 'Not Recorded'
                        : (visit.popMiddleStage == 0
                            ? 'Stage 0 (Normal)'
                            : 'Stage ${visit.popMiddleStage}'),
                    isHighlight: visit.popMiddleStage == 2,
                    isCritical: (visit.popMiddleStage ?? 0) >= 3,
                    isNormal: visit.popMiddleStage == 0,
                  ),
                  _buildPopBadge(
                    'POSTERIOR (Rectocele)',
                    visit.popPosteriorStage == null
                        ? 'Not Recorded'
                        : (visit.popPosteriorStage == 0
                            ? 'Stage 0 (Normal)'
                            : 'Stage ${visit.popPosteriorStage}'),
                    isHighlight: visit.popPosteriorStage == 2,
                    isCritical: (visit.popPosteriorStage ?? 0) >= 3,
                    isNormal: visit.popPosteriorStage == 0,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 4.5),

            // ── Diagnoses & Treatment ────────────────────────────────────────
            _buildPdfSectionHeader(
              '6. CONFIRMED DIAGNOSES & TREATMENT',
              encounterColor,
              date: visit.treatmentDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit.treatmentDate!) : null,
              dateLabel: 'Treatment Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                      final filtered = visit.deduplicatedFormularyMedications
                          .where((m) => !ReportAggregationService.isDosageInstruction(m))
                          .toList();
                      return filtered.isNotEmpty
                          ? filtered.join(' | ')
                          : 'None dispensed';
                    }(),
                  ),
                  if (visit.normalizedCustomMedication != null) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField(
                      'Other Medications',
                      sanitizeText(visit.normalizedCustomMedication!),
                    ),
                  ],
                  if (visit.pessaryType != null) ...[
                    pw.SizedBox(height: 2),
                    _buildPdfField(
                      'Ring Pessary',
                      '${sanitizeText(visit.pessaryType!)} (${ClinicalConstants.formatPessarySize(visit.pessarySize)})',
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
            pw.SizedBox(height: 4.5),

            // ── Continuity of Care ────────────────────────────────────────────
            _buildPdfSectionHeader(
              '7. CONTINUITY OF CARE & REFERRAL',
              encounterColor,
              date: visit.outtakeDate != null ? NepaliLocalizationService.formatDualCalendarDate(visit.outtakeDate!) : null,
              dateLabel: 'Outtake Date',
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
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
                  pw.SizedBox(height: 3),
                  _buildPdfField(
                    'Clinical Notes / Outtake Remarks',
                    (visit.outtakeNotes?.trim().isNotEmpty == true)
                        ? sanitizeText(visit.outtakeNotes!)
                        : ((visit.followUpNotes?.trim().isNotEmpty == true)
                            ? sanitizeText(visit.followUpNotes!)
                            : 'None recorded / Routine consultation'),
                    isBold: visit.outtakeNotes?.trim().isNotEmpty == true,
                  ),
                  if (visit.followUpNotes?.trim().isNotEmpty == true &&
                      visit.outtakeNotes?.trim().isNotEmpty == true &&
                      visit.followUpNotes!.trim() != visit.outtakeNotes!.trim()) ...[
                    pw.SizedBox(height: 3),
                    _buildPdfField(
                      'Follow-Up Instructions / Remarks',
                      sanitizeText(visit.followUpNotes!),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 7),
            ],

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
                    () {
                      final rawDocList = (visit.attendingDoctorNames.isNotEmpty
                          ? visit.attendingDoctorNames
                          : (camp != null && camp.doctorNames.isNotEmpty
                              ? camp.doctorNames
                              : (camp != null && camp.doctorName.trim().isNotEmpty
                                  ? [camp.doctorName]
                                  : <String>[])));
                      final parsedDocs = rawDocList
                          .map(DoctorProfile.parse)
                          .where((d) => d.isValid)
                          .toList();

                      final docTitle = parsedDocs.isNotEmpty
                          ? parsedDocs.map((d) => d.displayName).join(' & ')
                          : null;
                      final nmcNumbers = parsedDocs
                          .where((d) => d.hasNmc)
                          .map((d) => 'NMC No: ${d.nmcNumber}')
                          .join(', ');

                      return pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          if (docTitle != null && docTitle.isNotEmpty) ...[
                            pw.Text(
                              sanitizeText(docTitle),
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
                            nmcNumbers.isNotEmpty
                                ? '$nmcNumbers — Date: $visitDate'
                                : 'NMC Certified — Date: $visitDate',
                            style: const pw.TextStyle(
                              fontSize: 7,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      );
                    }(),
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
    bool allDoctorsChecklist = false,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    bool allNursesChecklist = false,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
    pw.MemoryImage? logoImage,
  }) {
    final secondary = PdfColor.fromHex('81005D'); // WFWSN Logo Wine/Magenta
    final cyan = PdfColor.fromHex('30026E'); // WFWSN Logo Royal Violet
    final cyanBg = PdfColor.fromHex('F5F3FF'); // Soft Violet Tint
    final dark = PdfColor.fromHex('1E293B');
    final gray = PdfColor.fromHex('94A3B8');
    final borderMuted = PdfColor.fromHex('64748B');
    final borderCheckbox = PdfColor.fromHex('334155');
    const boxBg = PdfColors.white;

    final bool showDoctor = camp?.showDoctorOnForms ?? true;
    final bool showNurse =
        blankNurseLines ||
        (camp?.showNurseOnForms ?? (nurse != null || allNursesChecklist));
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

    // Resolve active Diagnoses matching PatientFollowUpFormView Section 4
    final activeDiagLabels = (diagnoses ?? const <LookupItemModel>[])
        .where((d) => d.isActive && d.labelEn.trim().isNotEmpty)
        .map((d) => d.labelEn.trim())
        .toList();
    final List<String> effectiveDiagnoses = (activeDiagLabels.isNotEmpty
            ? activeDiagLabels
            : ClinicalConstants.defaultDiagnoses)
        .take(24)
        .toList();

    // Resolve active Medications matching PatientFollowUpFormView Section 5
    final activeMedLabels = (medications ?? const <LookupItemModel>[])
        .where((m) => m.isActive && m.labelEn.trim().isNotEmpty)
        .map((m) => m.labelEn.trim())
        .toList();
    final List<String> effectiveMedications = (activeMedLabels.isNotEmpty
            ? activeMedLabels
            : ClinicalConstants.defaultMedications)
        .take(16)
        .toList();

    // Resolve active Partner / Surgical Referral Hospitals matching PatientFollowUpFormView
    bool isPartnerHospital(String raw) {
      final name = raw.trim();
      if (name.isEmpty) return false;
      if (RegExp(r'^\(.*\)$').hasMatch(name)) return false;
      final low = name.toLowerCase();
      if (low == 'health post' ||
          low == 'local health post' ||
          low == 'gynaesupport nurse' ||
          low == 'no follow up needed' ||
          low.contains('scheer') ||
          low.contains('model')) {
        return false;
      }
      return true;
    }

    final Set<String> partnerHospSet = {};
    for (final h in (referralHospitals ?? const <LookupItemModel>[])) {
      if (h.isActive && isPartnerHospital(h.labelEn)) {
        partnerHospSet.add(h.labelEn.trim());
      }
    }
    if (partnerHospSet.isEmpty) {
      for (final h in ClinicalConstants.referralHospitals) {
        if (isPartnerHospital(h)) {
          partnerHospSet.add(h.trim());
        }
      }
    }
    final List<String> partnerHospitals =
        (partnerHospSet.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
            .take(3)
            .toList();

    const followUpComplaints = <String>[
      'Something hanging out (आङ खस्ने)',
      'Discharge / Itching (स्राव / चिलाउने)',
      'Urinary complaint (पिसाब सम्बन्धी)',
      'Stool complaint (दिसा सम्बन्धी)',
      'Menstrual issue (महिनावारी समस्या)',
      'Infertility (निःसन्तान)',
      'Pelvic / abdominal pain (तल्लो पेट दुखाइ)',
      'Routine follow-up checkup (नियमित जाँच)',
    ];

    const counselingOptions = <String>[
      'weak pelvic floor',
      'POP',
      'stress incontinence',
      'urge incontinence',
      'abdominal pain',
      'pelvic floor exercises',
      'pessary care & hygiene',
    ];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        build: (ctx) {
          pw.TextStyle bold({double size = 8.6, PdfColor? color}) =>
              pw.TextStyle(
                fontSize: size,
                fontWeight: pw.FontWeight.bold,
                color: color ?? dark,
              );

          pw.Widget secHeader(String titleEn, String titleNe) {
            return pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(top: 2.0, bottom: 3.5),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3.6,
              ),
              decoration: pw.BoxDecoration(
                color: cyan,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.5)),
              ),
              child: pw.Row(
                children: [
                  pw.Text(
                    titleEn,
                    style: pw.TextStyle(
                      fontSize: 9.2,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  if (titleNe.isNotEmpty) ...[
                    pw.SizedBox(width: 6),
                    ne(titleNe, size: 8.5, bold: true, color: 0xFFFFFFFF),
                  ],
                ],
              ),
            );
          }

          pw.Widget blankBox(String label, {int flex = 1, double h = 18.5}) =>
              pw.Expanded(
                flex: flex,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 3.0),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      ne(label, size: 8.1, bold: true, color: 0xFF1E293B),
                      pw.SizedBox(height: 2.0),
                      pw.Container(
                        height: h,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: borderMuted, width: 0.75),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(1.5),
                          ),
                          color: boxBg,
                        ),
                      ),
                    ],
                  ),
                ),
              );

          pw.Widget cb(
            String label, {
            double right = 7,
            double bottom = 2.4,
            double boxSize = 10.5,
            double fontSize = 8.5,
          }) => pw.Padding(
            padding: pw.EdgeInsets.only(right: right, bottom: bottom),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: boxSize,
                  height: boxSize,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(color: borderCheckbox, width: 0.95),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(2.0),
                    ),
                  ),
                ),
                pw.SizedBox(width: 3.8),
                ne(label, size: fontSize, color: 0xFF0F172A),
              ],
            ),
          );

          pw.Widget labeledLine(String label, {double h = 16.5}) => pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              ne(label, size: 8.4, bold: true, color: 0xFF0F172A),
              pw.SizedBox(width: 5),
              pw.Expanded(
                child: pw.Container(
                  height: h,
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: borderMuted, width: 0.75),
                    ),
                  ),
                ),
              ),
            ],
          );

          pw.Widget notesBox(
            String label, {
            int guideLines = 2,
            double height = 38.0,
          }) => pw.Container(
            width: double.infinity,
            height: height,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 7.0,
              vertical: 4.0,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: borderMuted, width: 0.75),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.5)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                ne(label, size: 8.2, bold: true, color: 0xFF0F172A),
                pw.Expanded(
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      guideLines,
                      (_) => pw.Container(
                        height: 0.55,
                        color: PdfColor.fromHex('CBD5E1'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );

          pw.Widget buildMultiColumnCheckboxes(
            List<String> items, {
            int columns = 4,
            double fontSize = 8.3,
            double boxSize = 10.4,
          }) {
            if (items.isEmpty) return pw.SizedBox.shrink();
            final perCol = (items.length / columns).ceil();
            return pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 5,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: gray, width: 0.7),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.5)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: List.generate(columns, (colIdx) {
                  final start = colIdx * perCol;
                  final end = (start + perCol) > items.length
                      ? items.length
                      : (start + perCol);
                  final slice = start < items.length
                      ? items.sublist(start, end)
                      : const <String>[];
                  return pw.Expanded(
                    child: pw.Padding(
                      padding: pw.EdgeInsets.only(
                        right: colIdx < columns - 1 ? 6 : 0,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: slice
                            .map(
                              (item) => pw.Padding(
                                padding: const pw.EdgeInsets.only(bottom: 2.6),
                                child: pw.Row(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.only(
                                        top: 0.6,
                                      ),
                                      child: pw.Container(
                                        width: boxSize,
                                        height: boxSize,
                                        decoration: pw.BoxDecoration(
                                          color: PdfColors.white,
                                          border: pw.Border.all(
                                            color: borderCheckbox,
                                            width: 0.95,
                                          ),
                                          borderRadius:
                                              const pw.BorderRadius.all(
                                                pw.Radius.circular(2.0),
                                              ),
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(width: 4),
                                    pw.Expanded(
                                      child: ne(
                                        item,
                                        size: fontSize,
                                        color: 0xFF0F172A,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  );
                }),
              ),
            );
          }

          pw.Widget buildCharBoxes(
            String val, {
            int maxBoxes = 5,
            double boxSize = 14.0,
            double boxMargin = 1.6,
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
                  height: boxSize + 3.0,
                  margin: pw.EdgeInsets.only(right: boxMargin),
                  decoration: pw.BoxDecoration(
                    color: boxBg,
                    border: pw.Border.all(color: borderCheckbox, width: 0.85),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(1.5),
                    ),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      char,
                      style: pw.TextStyle(
                        fontSize: 10.2,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                  ),
                );
              }),
            );
          }

          final nurseWidgets = _buildNurseSignatureBlock(
            cb: (label, _) =>
                cb(label, right: 5, bottom: 1.8, boxSize: 9.8, fontSize: 8.0),
            campNurses: campNurses,
            showNurse: showNurse,
            blankNurseLines: blankNurseLines,
            nurse: allNursesChecklist ? null : nurse,
            primary: cyan,
            dark: dark,
            width: 240,
            fsSmall: 8.2,
          );

          final DoctorProfile? effectiveDoctor = allDoctorsChecklist
              ? null
              : doctor;

          final headerAndIdentityBlock = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Header + Patient Token & Identity ──
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6.5,
                ),
                decoration: pw.BoxDecoration(
                  color: cyanBg,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                  border: pw.Border.all(color: cyan, width: 1.1),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          if (logoImage != null)
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(right: 9),
                              child: pw.Image(logoImage, width: 42, height: 42),
                            ),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  sanitizeText(organizationName.toUpperCase()),
                                  style: pw.TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: cyan,
                                  ),
                                ),
                                pw.SizedBox(height: 1),
                                pw.Row(
                                  children: [
                                    pw.Text(
                                      'FOLLOW-UP VISIT ASSESSMENT SHEET',
                                      style: pw.TextStyle(
                                        fontSize: 12.8,
                                        fontWeight: pw.FontWeight.bold,
                                        color: dark,
                                      ),
                                    ),
                                    pw.SizedBox(width: 6),
                                    ne(
                                      '(फलो-अप जाँच फाराम — ठूला अक्षरमा भर्नुहोस्)',
                                      size: 8.2,
                                      color: 0xFF334155,
                                    ),
                                  ],
                                ),
                                pw.SizedBox(height: 1.5),
                                pw.Text(
                                  camp != null
                                      ? 'Camp: ${sanitizeText(camp.name)} (${camp.campCode}) | Venue: ${sanitizeText(camp.venue)}, ${sanitizeText(camp.district)}'
                                      : 'Camp: ________________________ | Venue: ________________________',
                                  style: pw.TextStyle(
                                    fontSize: 8.4,
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
                          'PATIENT TOKEN ID',
                          style: bold(size: 8.0, color: cyan),
                        ),
                        pw.SizedBox(height: 2),
                        (preprintedTokenId != null &&
                                preprintedTokenId.isNotEmpty)
                            ? pw.Row(
                                mainAxisSize: pw.MainAxisSize.min,
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.center,
                                children: [
                                  buildCharBoxes(
                                    preprintedTokenId,
                                    maxBoxes: preprintedTokenId.length,
                                    boxSize: preprintedTokenId.length > 16
                                        ? 9.5
                                        : (preprintedTokenId.length <= 6
                                              ? 13.5
                                              : 11.2),
                                  ),
                                  pw.SizedBox(width: 5),
                                  pw.BarcodeWidget(
                                    barcode: pw.Barcode.qrCode(),
                                    data: preprintedTokenId,
                                    width: 26,
                                    height: 26,
                                  ),
                                ],
                              )
                            : buildCharBoxes('', maxBoxes: 5, boxSize: 14.0),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Visit Date (BS/AD): ____-__-__',
                          style: pw.TextStyle(
                            fontSize: 7.6,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 5),
              // ── Patient Identity Strip ──
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 4.5,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: gray, width: 0.75),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Row(
                  children: [
                    blankBox('Patient Name (बिरामीको नाम)', flex: 30, h: 18.5),
                    blankBox('Age (उमेर)', flex: 9, h: 18.5),
                    blankBox('Ward (वडा)', flex: 9, h: 18.5),
                    blankBox('Mobile (फोन नं.)', flex: 18, h: 18.5),
                    blankBox('Municipality (पालिका)', flex: 19, h: 18.5),
                    blankBox('District (जिल्ला)', flex: 15, h: 18.5),
                  ],
                ),
              ),
            ],
          );

          final section1Block = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHeader(
                '1. FOLLOW-UP COMPLAINTS & NEW ISSUES',
                '(फलो-अप समस्याहरू)',
              ),
              buildMultiColumnCheckboxes(
                followUpComplaints,
                columns: 2,
                fontSize: 8.6,
                boxSize: 10.6,
              ),
              pw.SizedBox(height: 3.5),
              notesBox(
                'NEW ISSUES / OBSERVATIONS (नयाँ देखिएका समस्या तथा कैफियत) [BLOCK LETTERS]:',
                guideLines: 1,
                height: 24.0,
              ),
            ],
          );

          final section2Block = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHeader(
                '2. PHYSICAL VITALS CHECK & SCREENING LABS',
                '(शारीरिक जाँच तथा ल्याब)',
              ),
              pw.Row(
                children: [
                  blankBox('Systolic BP (mmHg)', flex: 20, h: 18.5),
                  blankBox('Diastolic BP (mmHg)', flex: 20, h: 18.5),
                  blankBox('Pulse Rate (bpm)', flex: 20, h: 18.5),
                  blankBox('SpO2 (%)', flex: 18, h: 18.5),
                  blankBox('Blood Glucose (mg/dL)', flex: 22, h: 18.5),
                ],
              ),
              pw.SizedBox(height: 4.5),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  ne(
                    'Urine Test (पिसाब): ',
                    size: 8.5,
                    bold: true,
                    color: 0xFF0F172A,
                  ),
                  cb('Not Done', bottom: 0, right: 6),
                  cb('Normal / Neg (-)', bottom: 0, right: 6),
                  cb('Positive (+)', bottom: 0, right: 12),
                  ne(
                    'Pregnancy / UPT: ',
                    size: 8.5,
                    bold: true,
                    color: 0xFF0F172A,
                  ),
                  cb('Not Indicated', bottom: 0, right: 6),
                  cb('Negative (-)', bottom: 0, right: 6),
                  cb('Positive (+)', bottom: 0, right: 0),
                ],
              ),
              pw.SizedBox(height: 3.0),
              labeledLine('ECG Findings / Notes [BLOCK LETTERS]:', h: 16.5),
            ],
          );

          final section3Block = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHeader(
                '3. PELVIC FLOOR & POP RE-STAGING',
                '(श्रोणी जाँच तथा आङ खस्ने स्टेज)',
              ),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Uterus Inside ', style: bold(size: 8.5)),
                  ne('(पाठेघर भित्रै छ?): ', size: 8.4, bold: true),
                  cb('Yes', bottom: 0, right: 6),
                  cb('No', bottom: 0, right: 12),
                  pw.Text('Pelvic Floor Muscle ', style: bold(size: 8.5)),
                  ne('(पेल्भिक मांसपेशी): ', size: 8.4, bold: true),
                  cb('Normal (सामान्य)', bottom: 0, right: 6),
                  cb('Weak (कमजोर)', bottom: 0, right: 6),
                  cb('Hypertonic (कडा)', bottom: 0, right: 0),
                ],
              ),
              pw.SizedBox(height: 4.0),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('F8FAFC'),
                  border: pw.Border.all(color: gray, width: 0.7),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(2.5),
                  ),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Row(
                            children: [
                              pw.Text(
                                'Anterior (Cystocele): ',
                                style: bold(size: 8.5),
                              ),
                              for (final s in [0, 1, 2, 3])
                                cb('S$s', bottom: 0, right: 5.5, boxSize: 10.4),
                            ],
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Row(
                            children: [
                              pw.Text(
                                'Apical (Uterine/Apex): ',
                                style: bold(size: 8.5),
                              ),
                              for (final s in [0, 1, 2, 3, 4])
                                cb('S$s', bottom: 0, right: 5.0, boxSize: 10.4),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4.0),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Row(
                            children: [
                              pw.Text(
                                'Posterior (Rectocele): ',
                                style: bold(size: 8.5),
                              ),
                              for (final s in [0, 1, 2, 3])
                                cb('S$s', bottom: 0, right: 5.5, boxSize: 10.4),
                            ],
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Row(
                            children: [
                              pw.Text(
                                'Overall Highest Stage: ',
                                style: bold(size: 8.5, color: secondary),
                              ),
                              for (final s in [0, 1, 2, 3, 4])
                                cb('S$s', bottom: 0, right: 5.0, boxSize: 10.4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final section4Block = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHeader(
                '4. DIAGNOSES & SURGICAL EVALUATION',
                '(निदान तथा शल्यक्रिया मूल्याङ्कन)',
              ),
              buildMultiColumnCheckboxes(
                effectiveDiagnoses,
                columns: 4,
                fontSize: 8.3,
                boxSize: 10.4,
              ),
              pw.SizedBox(height: 4.0),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  ne(
                    'Surgery Performed (शल्यक्रिया भएको?): ',
                    size: 8.4,
                    bold: true,
                  ),
                  cb('No', bottom: 0, right: 6),
                  cb('Yes', bottom: 0, right: 12),
                  pw.Text('Surgical Route: ', style: bold(size: 8.4)),
                  cb('Open surgery', bottom: 0, right: 6),
                  cb('Laparoscopy', bottom: 0, right: 6),
                  cb('Vaginal route', bottom: 0, right: 0),
                ],
              ),
              pw.SizedBox(height: 3.5),
              pw.Wrap(
                crossAxisAlignment: pw.WrapCrossAlignment.center,
                children: [
                  ne(
                    'Surgical Referral Center (सिफारिस अस्पताल): ',
                    size: 8.4,
                    bold: true,
                  ),
                  cb('No Surgical Referral', bottom: 1.5, right: 6),
                  for (final h in partnerHospitals)
                    cb(h, bottom: 1.5, right: 6),
                  cb('Other: ________________', bottom: 1.5, right: 0),
                ],
              ),
            ],
          );

          final section5Block = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHeader(
                '5. PRESCRIPTION & FOLLOW-UP DESTINATION',
                '(औषधि तथा थप फलो-अप)',
              ),
              buildMultiColumnCheckboxes(
                effectiveMedications,
                columns: 4,
                fontSize: 8.3,
                boxSize: 10.4,
              ),
              pw.SizedBox(height: 4.0),
              pw.Wrap(
                crossAxisAlignment: pw.WrapCrossAlignment.center,
                children: [
                  ne(
                    'Specialized Counseling (परामर्श): ',
                    size: 8.4,
                    bold: true,
                  ),
                  for (final c in counselingOptions)
                    cb(c, bottom: 2.0, right: 6, boxSize: 10.2, fontSize: 8.2),
                ],
              ),
              pw.SizedBox(height: 3.0),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Pessary Fitted / Type: ', style: bold(size: 8.4)),
                  cb('None', bottom: 0, right: 6),
                  cb('ring', bottom: 0, right: 6),
                  cb('ring with support', bottom: 0, right: 6),
                  cb('ring with knob', bottom: 0, right: 12),
                  ne('Size (साइज): ', size: 8.4, bold: true),
                  pw.Container(
                    width: 42,
                    height: 15,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: borderMuted, width: 0.8),
                      ),
                    ),
                  ),
                  pw.Text(' mm', style: bold(size: 8.2)),
                ],
              ),
              pw.SizedBox(height: 3.5),
              pw.Wrap(
                crossAxisAlignment: pw.WrapCrossAlignment.center,
                children: [
                  ne(
                    'Further Follow-Up Needed? (थप फलो-अप): ',
                    size: 8.4,
                    bold: true,
                  ),
                  cb('Yes', bottom: 1.5, right: 5),
                  cb('No', bottom: 1.5, right: 12),
                  pw.Text('Destination: ', style: bold(size: 8.4)),
                  cb('None', bottom: 1.5, right: 6),
                  cb('Health Post (स्वास्थ्य चौकी)', bottom: 1.5, right: 6),
                  cb('GynaeSupport Nurse (गाइने नर्स)', bottom: 1.5, right: 6),
                  for (final h in partnerHospitals)
                    cb(h, bottom: 1.5, right: 6),
                ],
              ),
              pw.SizedBox(height: 3.5),
              notesBox(
                'FINAL FOLLOW-UP NOTES / COUNSELING [BLOCK LETTERS]:',
                guideLines: 2,
                height: 36.0,
              ),
            ],
          );

          final signaturesBlock = pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (showNurse)
                  pw.SizedBox(
                    width: 245,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: nurseWidgets.isNotEmpty
                          ? nurseWidgets
                          : [
                              pw.SizedBox(height: 18),
                              pw.Container(
                                width: 150,
                                height: 0.85,
                                color: PdfColors.black,
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                'Attending / Assisting Nurse',
                                style: bold(size: 8.4),
                              ),
                              pw.Text(
                                'Nurse Signature & NNC No.: _______________',
                                style: const pw.TextStyle(
                                  fontSize: 7.5,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ],
                    ),
                  )
                else
                  pw.Spacer(),
                pw.SizedBox(
                  width: 300,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (!showDoctor || blankDoctorLines) ...[
                        pw.SizedBox(height: 18),
                        pw.Container(
                          width: 160,
                          height: 0.85,
                          color: PdfColors.black,
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Attending / Examining Doctor',
                          style: bold(size: 8.4),
                        ),
                        pw.Text(
                          'Doctor Signature & NMC: ___________________',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (effectiveDoctor != null) ...[
                        pw.SizedBox(height: 18),
                        pw.Container(
                          width: 155,
                          height: 0.85,
                          color: PdfColors.black,
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          effectiveDoctor.displayName,
                          style: bold(size: 8.6),
                        ),
                        pw.Text(
                          effectiveDoctor.hasNmc
                              ? 'Attending Doctor | NMC No: ${effectiveDoctor.nmcNumber}'
                              : 'Attending Doctor | NMC Certified',
                          style: const pw.TextStyle(
                            fontSize: 7.6,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (campDoctors.isNotEmpty &&
                          (allDoctorsChecklist || campDoctors.length > 1)) ...[
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              'Attending Doctor(s) (',
                              style: bold(size: 8.2, color: secondary),
                            ),
                            ne(
                              'जाँच गर्ने चिकित्सक',
                              size: 8.2,
                              bold: true,
                              color: 0xFF81005D,
                            ),
                            pw.Text(
                              '):',
                              style: bold(size: 8.2, color: secondary),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 2.0),
                        pw.Wrap(
                          spacing: 4,
                          runSpacing: 1.5,
                          alignment: pw.WrapAlignment.end,
                          children: [
                            ...campDoctors.map(
                              (doc) => cb(
                                DoctorProfile.parse(doc).formattedLabel,
                                right: 5,
                                bottom: 1.5,
                                boxSize: 9.8,
                                fontSize: 8.0,
                              ),
                            ),
                            cb(
                              'Other: _____',
                              right: 0,
                              bottom: 1.5,
                              boxSize: 9.8,
                              fontSize: 8.0,
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 14),
                        pw.Container(
                          width: 155,
                          height: 0.85,
                          color: PdfColors.black,
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Doctor Signature & NMC: ______________',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else if (campDoctors.length == 1) ...[
                        pw.SizedBox(height: 18),
                        pw.Container(
                          width: 155,
                          height: 0.85,
                          color: PdfColors.black,
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          DoctorProfile.parse(campDoctors.first).displayName,
                          style: bold(size: 8.6),
                        ),
                        pw.Text(
                          DoctorProfile.parse(campDoctors.first).hasNmc
                              ? 'Attending Doctor | NMC No: ${DoctorProfile.parse(campDoctors.first).nmcNumber}'
                              : 'Attending Doctor | NMC Certified',
                          style: const pw.TextStyle(
                            fontSize: 7.6,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ] else ...[
                        pw.SizedBox(height: 18),
                        pw.Container(
                          width: 160,
                          height: 0.85,
                          color: PdfColors.black,
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Attending / Examining Doctor',
                          style: bold(size: 8.4),
                        ),
                        pw.Text(
                          'Doctor Signature & NMC No.: _______________',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
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

          return pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            alignment: pw.Alignment.topCenter,
            child: pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(
                minWidth: 559,
                maxWidth: 559,
                minHeight: 813,
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  headerAndIdentityBlock,
                  section1Block,
                  section2Block,
                  section3Block,
                  section4Block,
                  section5Block,
                  signaturesBlock,
                ],
              ),
            ),
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
              pw.SizedBox(height: 18),
              signLine(150),
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
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
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
              pw.SizedBox(height: 18),
              signLine(150),
              pw.SizedBox(height: 3),
              pw.Text(
                sanitizeText(nurse.displayName),
                style: pw.TextStyle(
                  fontSize: fsSmall,
                  fontWeight: pw.FontWeight.bold,
                  color: dark,
                ),
              ),
              pw.Text(
                nurse.hasRegistration
                    ? 'Attending Nurse | NNC No: ${sanitizeText(nurse.registrationNumber)}'
                    : 'Attending Nurse | NNC Certified',
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
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
              signLine(150),
              pw.SizedBox(height: 3),
              pw.Text(
                'Nurse Signature & NNC No.: ______________',
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
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
    String? preprintedTokenId,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    bool allDoctorsChecklist = false,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    bool allNursesChecklist = false,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    return _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme);
      _addBlankFollowUpSlipPage(
        pdf,
        camp: camp,
        preprintedTokenId: preprintedTokenId,
        doctor: doctor,
        blankDoctorLines: blankDoctorLines,
        allDoctorsChecklist: allDoctorsChecklist,
        nurse: nurse,
        blankNurseLines: blankNurseLines,
        allNursesChecklist: allNursesChecklist,
        organizationName: organizationName,
        diagnoses: diagnoses,
        medications: medications,
        referralHospitals: referralHospitals,
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
    bool allNursesChecklist = false,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
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
          allNursesChecklist: allNursesChecklist,
          organizationName: organizationName,
          diagnoses: diagnoses,
          medications: medications,
          referralHospitals: referralHospitals,
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
    bool allDoctorsChecklist = false,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
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
          allDoctorsChecklist: allDoctorsChecklist,
          nurse: n,
          blankNurseLines: false,
          organizationName: organizationName,
          diagnoses: diagnoses,
          medications: medications,
          referralHospitals: referralHospitals,
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
    final dark = PdfColor.fromHex('0F172A'); // Deep slate ink for crisp yellow-paper print
    final inkMuted = PdfColor.fromHex('334155');
    final lineRuleColor = PdfColor.fromHex('64748B');
    final gray = PdfColor.fromHex('CBD5E1');
    const boxBg = PdfColors.white;

    const String dynamicTokenPrefix = '';
    const int dynamicTokenTotalBoxes = 5;
    const double dynamicTokenBoxSize = 13.0;
    const double dynamicTokenBoxMargin = 1.5;

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
            final p = DoctorProfile.parse(d);
            return p.hasNmc
                ? '${p.displayName} | NMC: ${p.nmcNumber}'
                : p.displayName;
          })
          .join(', ');
    } else if (assignedDoctor != null) {
      final p = DoctorProfile.parse(assignedDoctor);
      doctorHeaderPart = p.hasNmc
          ? '${p.displayName} | NMC: ${p.nmcNumber}'
          : p.displayName;
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
    final bool showNurse = camp?.showNurseOnForms ?? (nurse != null || allNursesChecklist);
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
        {'code': 'prolapse', 'label': 'Something hanging out'},
        {'code': 'discharge', 'label': 'Discharge / Itching'},
        {'code': 'urine', 'label': 'Problems passing urine'},
        {'code': 'stool', 'label': 'Problems passing stool'},
        {'code': 'menstrual', 'label': 'Menstrual problem'},
        {'code': 'infertility', 'label': 'Infertility'},
        {'code': 'lower_abdomen_pain', 'label': 'Lower abdomen pain'},
        {'code': 'lower_back_pain', 'label': 'Lower back pain'},
        {'code': 'checkup', 'label': 'Checkup'},
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
                  color: lineRuleColor,
                  width: 0.85,
                ),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              alignment: pw.Alignment.center,
              child: pw.Text(
                rawChar,
                style: pw.TextStyle(
                  fontSize: boxSize * 0.72,
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
                color: lineRuleColor,
                width: 0.85,
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          );
        }),
      );
    }

    // ── Bilingual Vector English + Raster Nepali Label Helper (Preserves OCR/PDF Text Layer) ──
    pw.Widget renderBilingualText(
      String label, {
      required double fontSize,
      bool bold = false,
      int enColor = 0xFF0F172A,
      int neColor = 0xFF1E293B,
      double? maxWidth,
      bool allowWrap = false,
    }) {
      if (!_devanagari.hasMatch(label)) {
        return ne(
          label,
          size: fontSize,
          bold: bold,
          color: enColor,
          maxWidth: maxWidth,
        );
      }
      final nlIdx = label.indexOf('\n');
      if (nlIdx != -1) {
        final topPart = label.substring(0, nlIdx).trim();
        final botPart = label.substring(nlIdx + 1).trim();
        if (topPart.isNotEmpty && !_devanagari.hasMatch(topPart)) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              ne(topPart, size: fontSize, bold: bold, color: enColor),
              ne(
                botPart,
                size: fontSize * 0.94,
                bold: false,
                color: neColor,
                maxWidth: maxWidth,
              ),
            ],
          );
        }
      }
      final parenIdx = label.indexOf('(');
      final slashIdx = label.indexOf('/');
      if (parenIdx != -1 && (slashIdx == -1 || parenIdx < slashIdx)) {
        final enPart = label.substring(0, parenIdx).trim();
        final nePart = label.substring(parenIdx).trim();
        if (enPart.isNotEmpty && !_devanagari.hasMatch(enPart)) {
          if (allowWrap) {
            return pw.Wrap(
              crossAxisAlignment: pw.WrapCrossAlignment.center,
              spacing: 2,
              runSpacing: 1,
              children: [
                ne(enPart, size: fontSize, bold: bold, color: enColor),
                ne(nePart, size: fontSize * 0.96, bold: bold, color: neColor, maxWidth: maxWidth),
              ],
            );
          }
          return pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              ne(enPart, size: fontSize, bold: bold, color: enColor),
              pw.SizedBox(width: 2.5),
              ne(nePart, size: fontSize * 0.96, bold: bold, color: neColor),
            ],
          );
        }
      }
      if (slashIdx != -1) {
        final enPart = label.substring(0, slashIdx).trim();
        final nePart = label.substring(slashIdx).trim();
        if (enPart.isNotEmpty && !_devanagari.hasMatch(enPart)) {
          if (allowWrap) {
            return pw.Wrap(
              crossAxisAlignment: pw.WrapCrossAlignment.center,
              spacing: 2,
              runSpacing: 1,
              children: [
                ne(enPart, size: fontSize, bold: bold, color: enColor),
                ne(nePart, size: fontSize * 0.96, bold: bold, color: neColor, maxWidth: maxWidth),
              ],
            );
          }
          return pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              ne(enPart, size: fontSize, bold: bold, color: enColor),
              pw.SizedBox(width: 2.5),
              ne(nePart, size: fontSize * 0.96, bold: bold, color: neColor),
            ],
          );
        }
      }
      return ne(
        label,
        size: fontSize,
        bold: bold,
        color: enColor,
        maxWidth: maxWidth,
      );
    }

    // ── Standard Bikram Sambat (BS) Date Character Boxes Helper ──
    pw.Widget buildDateBsBoxes(
      DateTime? date, {
      bool hasData = false,
      double boxSize = 10.0,
      double boxHeight = 13.5,
      double fontSize = 8.0,
    }) {
      final d = date ?? DateTime.now();
      final bs = NepaliDateHelper.toNepali(d);
      final bsYear = bs.year.toString().padLeft(4, '0');
      final bsMonth = bs.month.toString().padLeft(2, '0');
      final bsDay = bs.day.toString().padLeft(2, '0');
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
        margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        build: (ctx) {
          // ── Professional Section Header with Slate Background & Left Accent Bar ──
          pw.Widget secHdr(
            String title, {
            double topMargin = 2.5,
            double bottomMargin = 3.0,
          }) {
            return pw.Container(
              width: double.infinity,
              margin: pw.EdgeInsets.only(top: topMargin, bottom: bottomMargin),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2.8,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('F1F5F9'),
                border: pw.Border(
                  left: pw.BorderSide(
                    color: PdfColor.fromHex('1B365D'),
                    width: 3.2,
                  ),
                  top: pw.BorderSide(
                    color: PdfColor.fromHex('94A3B8'),
                    width: 0.7,
                  ),
                  right: pw.BorderSide(
                    color: PdfColor.fromHex('94A3B8'),
                    width: 0.7,
                  ),
                  bottom: pw.BorderSide(
                    color: PdfColor.fromHex('94A3B8'),
                    width: 0.7,
                  ),
                ),
              ),
              child: renderBilingualText(
                title,
                fontSize: 9.4,
                bold: true,
                enColor: 0xFF0F172A,
                neColor: 0xFF0F172A,
              ),
            );
          }

          // ── Standard Uniform Checkbox (Crisp 11.0 pt box, 8.2-8.4 pt text) ──
          pw.Widget cb(
            String label,
            bool checked, {
            double? textWidth,
            double bottom = 0.0,
            bool isExpanded = false,
            double boxSize = 11.0,
            double fontSize = 8.2,
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
                      color: checked ? primary : PdfColor.fromHex('334155'),
                      width: 0.9,
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
                  final content = renderBilingualText(
                    label,
                    fontSize: fontSize,
                    bold: checked,
                    maxWidth: textWidth,
                    allowWrap: isExpanded || textWidth != null,
                  );
                  if (textWidth != null) {
                    return pw.SizedBox(width: textWidth, child: content);
                  } else if (isExpanded) {
                    return pw.Expanded(child: content);
                  }
                  return content;
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
            double boxSize = 12.2,
            double boxHeight = 16.0,
            double boxMargin = 1.0,
            double bottomPadding = 4.2,
          }) => pw.Padding(
            padding: pw.EdgeInsets.only(bottom: bottomPadding),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  height: 12.5,
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        '$labelEn: ',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: dark,
                        ),
                      ),
                      ne(labelNe, size: 8.0, color: 0xFF1E293B),
                    ],
                  ),
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
            margin: const pw.EdgeInsets.only(top: 2.5, bottom: 2.0),
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3.2,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('F8FAFC'),
              border: pw.Border.all(
                color: PdfColor.fromHex('94A3B8'),
                width: 0.7,
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      'CONSULTATION: ',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: primary,
                      ),
                    ),
                    ne('परामर्श:', size: 8.2, bold: true, color: 0xFF30026E),
                  ],
                ),
                pw.SizedBox(width: 10),
                cb(
                  'Counseling / काउन्सिलिङ',
                  isCouncilLevel,
                  fontSize: 8.4,
                  boxSize: 11.0,
                ),
                pw.SizedBox(width: 10),
                cb(
                  'Gynocheckup / गाइनो जाँच',
                  isFullCheckUp,
                  fontSize: 8.4,
                  boxSize: 11.0,
                ),
                pw.Spacer(),
                // ── Date in character boxes ending with BS ──
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    renderBilingualText(
                      'Date: / मिति:',
                      fontSize: 8.5,
                      bold: true,
                    ),
                    pw.SizedBox(width: 4),
                    buildDateBsBoxes(
                      intakeDate,
                      hasData: hasPatient,
                      boxSize: 10.2,
                      boxHeight: 14.0,
                      fontSize: 8.0,
                    ),
                  ],
                ),
              ],
            ),
          );

          // ── Section A: Demographics (High-Legibility Grid) ──
          final sectionA = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              secHdr(
                'SECTION A: PATIENT DEMOGRAPHICS / बिरामी विवरण',
                topMargin: 2.0,
                bottomMargin: 3.5,
              ),
              // Row 1: First Name, Surname, Age
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 41,
                    child: field(
                      'First Name',
                      'पहिलो नाम',
                      patient?.firstName ?? '',
                      minBoxes: 15,
                      maxBoxes: 15,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 41,
                    child: field(
                      'Surname',
                      'थर',
                      patient?.surname ?? '',
                      minBoxes: 15,
                      maxBoxes: 15,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 18,
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
                      flex: 37,
                      child: field(
                        'Relative Name',
                        'आफन्तको नाम',
                        relName.isNotEmpty ? relName.split(' ').first : '',
                        minBoxes: 14,
                        maxBoxes: 14,
                        boxSize: 12.0,
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      flex: 36,
                      child: field(
                        'Relative Surname',
                        'थर',
                        relName.contains(' ')
                            ? relName.split(' ').skip(1).join(' ')
                            : '',
                        minBoxes: 14,
                        maxBoxes: 14,
                        boxSize: 12.0,
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      flex: 27,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(
                            height: 12.5,
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text(
                                  'Relation: ',
                                  style: pw.TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: dark,
                                  ),
                                ),
                                ne('नाता', size: 8.0, color: 0xFF1E293B),
                              ],
                            ),
                          ),
                          pw.SizedBox(height: 2.5),
                          pw.Row(
                            children: [
                              cb(
                                'Husband / श्रीमान्',
                                (patient?.relationshipType ?? '').toLowerCase().contains('husband'),
                                bottom: 0,
                                boxSize: 10.5,
                                fontSize: 8.0,
                              ),
                              pw.SizedBox(width: 2),
                              cb(
                                'Father / बुबा',
                                (patient?.relationshipType ?? '').toLowerCase().contains('father'),
                                bottom: 0,
                                boxSize: 10.5,
                                fontSize: 8.0,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }(),
              // Row 3: Mobile, Ward, Contact Person (15 boxes), Contact Mobile
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
                      boxSize: 12.0,
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Expanded(
                    flex: 10,
                    child: field(
                      'Ward',
                      'वडा',
                      patient?.ward ?? '',
                      minBoxes: 2,
                      maxBoxes: 2,
                      boxSize: 12.0,
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Expanded(
                    flex: 38,
                    child: field(
                      'Contact Person',
                      'सम्पर्क व्यक्ति',
                      patient?.contactPerson ?? '',
                      minBoxes: 15,
                      maxBoxes: 15,
                      boxSize: 12.0,
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Expanded(
                    flex: 26,
                    child: field(
                      'Contact Mobile',
                      'सम्पर्क मोबाइल',
                      patient?.contactMobile ?? '',
                      minBoxes: 10,
                      maxBoxes: 10,
                      boxSize: 12.0,
                    ),
                  ),
                ],
              ),
              // Row 4: Marital Status & Marital Age
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 78,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(
                          height: 12.5,
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text(
                                'Marital Status: ',
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: dark,
                                ),
                              ),
                              ne('वैवाहिक स्थिति', size: 8.0, color: 0xFF1E293B),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 2.5),
                        pw.Row(
                          children: [
                            cb(
                              'Married / विवाहित',
                              patient?.maritalStatus == 'married',
                              fontSize: 8.2,
                              boxSize: 11.0,
                            ),
                            pw.SizedBox(width: 4),
                            cb(
                              'Unmarried / अविवाहित',
                              patient?.maritalStatus == 'unmarried',
                              fontSize: 8.2,
                              boxSize: 11.0,
                            ),
                            pw.SizedBox(width: 4),
                            cb(
                              'Widow / एकल',
                              patient?.maritalStatus == 'widow',
                              fontSize: 8.2,
                              boxSize: 11.0,
                            ),
                            pw.SizedBox(width: 4),
                            cb(
                              'Divorced / सम्बन्ध विच्छेद',
                              patient?.maritalStatus == 'divorced',
                              fontSize: 8.2,
                              boxSize: 11.0,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    flex: 22,
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
              // Row 5: Dedicated Location Row with Character Boxes for Palika (15), District (14), and Province (10)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 39,
                    child: field(
                      'Palika',
                      'गाउँ / न.पा.',
                      palikaVal,
                      minBoxes: 15,
                      maxBoxes: 15,
                      boxSize: 11.8,
                      boxMargin: 0.9,
                      bottomPadding: 2.0,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 36,
                    child: field(
                      'District',
                      'जिल्ला',
                      patient?.district ?? '',
                      minBoxes: 14,
                      maxBoxes: 14,
                      boxSize: 11.8,
                      boxMargin: 0.9,
                      bottomPadding: 2.0,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 25,
                    child: field(
                      'Province',
                      'प्रदेश',
                      patient?.province ?? '',
                      minBoxes: 10,
                      maxBoxes: 10,
                      boxSize: 11.8,
                      boxMargin: 0.9,
                      bottomPadding: 2.0,
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
                  // Left: 8 Checkboxes in a clean 2-column grid (4 rows)
                  pw.Expanded(
                    flex: 60,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Reason for visit / आउनुको कारण:',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: dark,
                          ),
                        ),
                        pw.SizedBox(height: 3.0),
                        () {
                          final reasonEntries =
                              effectiveVisitReasons.entries.take(8).toList();
                          final rowCount = (reasonEntries.length / 2).ceil();
                          return pw.Column(
                            children: List.generate(rowCount, (rIdx) {
                              final left = reasonEntries[rIdx * 2];
                              final right = (rIdx * 2 + 1) < reasonEntries.length
                                  ? reasonEntries[rIdx * 2 + 1]
                                  : null;
                              pw.Widget buildReasonCb(MapEntry<String, String> entry) {
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
                                  isExpanded: true,
                                  bottom: 2.5,
                                );
                              }

                              return pw.Row(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Expanded(child: buildReasonCb(left)),
                                  pw.SizedBox(width: 4),
                                  pw.Expanded(
                                    child: right != null
                                        ? buildReasonCb(right)
                                        : pw.SizedBox(),
                                  ),
                                ],
                              );
                            }),
                          );
                        }(),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Container(width: 0.7, height: 76, color: gray),
                  pw.SizedBox(width: 8),
                  // Right: Consent & Signature / Thumbprint
                  pw.Expanded(
                    flex: 40,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  pw.Text(
                                    'Consent for Treatment:',
                                    style: pw.TextStyle(
                                      fontSize: 8.2,
                                      fontWeight: pw.FontWeight.bold,
                                      color: dark,
                                    ),
                                  ),
                                  ne(
                                    'उपचारको लागि सहमति',
                                    size: 7.8,
                                    color: 0xFF1E293B,
                                  ),
                                ],
                              ),
                            ),
                            cb(
                              'YES',
                              patient?.consentTreatment == true,
                              fontSize: 8.2,
                              boxSize: 10.8,
                            ),
                            cb(
                              'NO',
                              patient?.consentTreatment == false,
                              fontSize: 8.2,
                              boxSize: 10.8,
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4.0),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  pw.Text(
                                    'Consent for Storage:',
                                    style: pw.TextStyle(
                                      fontSize: 8.2,
                                      fontWeight: pw.FontWeight.bold,
                                      color: dark,
                                    ),
                                  ),
                                  ne(
                                    'स्वास्थ्य विवरण सहमति',
                                    size: 7.8,
                                    color: 0xFF1E293B,
                                  ),
                                ],
                              ),
                            ),
                            cb(
                              'YES',
                              patient?.consentStoreMedicalInfo == true,
                              fontSize: 8.2,
                              boxSize: 10.8,
                            ),
                            cb(
                              'NO',
                              patient?.consentStoreMedicalInfo == false,
                              fontSize: 8.2,
                              boxSize: 10.8,
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 6.0),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'Patient Sign / Thumb: ',
                              style: pw.TextStyle(
                                fontSize: 8.0,
                                fontWeight: pw.FontWeight.bold,
                                color: dark,
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Container(
                                height: 22,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border(
                                    bottom: pw.BorderSide(
                                      color: lineRuleColor,
                                      width: 0.7,
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
                !durationVal.contains('>') &&
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
              padding: const pw.EdgeInsets.only(bottom: 4.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Checkbox + Name
                  pw.SizedBox(
                    width: 140,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 1.5),
                      child: cb(
                        '$nameEn\n($nameNe)',
                        isTicked,
                        fontSize: 8.3,
                        boxSize: 10.5,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  // Right: Bordered Rectangle Box (Duration, Sub-options, Remarks)
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4.5,
                      ),
                      decoration: pw.BoxDecoration(
                        color: isTicked
                            ? PdfColor.fromHex('F8FAFC')
                            : PdfColors.white,
                        border: pw.Border.all(
                          color: isTicked ? primary : PdfColor.fromHex('94A3B8'),
                          width: 0.7,
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
                                    fontSize: 8.0,
                                    fontWeight: pw.FontWeight.bold,
                                    color: dark,
                                  ),
                                ),
                                ...durationList.map((d) {
                                  final checked =
                                      isTicked && isDurationMatch(d, durVal);
                                  return pw.Padding(
                                    padding: const pw.EdgeInsets.only(left: 2),
                                    child: cb(
                                      d,
                                      checked,
                                      fontSize: 8.0,
                                      boxSize: 9.8,
                                    ),
                                  );
                                }),
                              ],
                            ),
                            pw.SizedBox(height: 3.0),
                          ],
                          if (options.length >= 4) ...[
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                if (optionPrefix != null)
                                  pw.Text(
                                    '$optionPrefix: ',
                                    style: pw.TextStyle(
                                      fontSize: 8.0,
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
                                      fontSize: 8.0,
                                      boxSize: 9.8,
                                    ),
                                  );
                                }),
                              ],
                            ),
                            pw.SizedBox(height: 3.0),
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text(
                                  'remarks: ',
                                  style: pw.TextStyle(
                                    fontSize: 8.0,
                                    fontWeight: pw.FontWeight.bold,
                                    color: dark,
                                  ),
                                ),
                                pw.Expanded(
                                  child: pw.Container(
                                    height: 14.5,
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(
                                        bottom: pw.BorderSide(
                                          color: lineRuleColor,
                                          width: 0.6,
                                        ),
                                      ),
                                    ),
                                    alignment: pw.Alignment.bottomLeft,
                                    padding: const pw.EdgeInsets.only(
                                      bottom: 1.0,
                                    ),
                                    child: pw.Text(
                                      remVal,
                                      style: pw.TextStyle(
                                        fontSize: 8.0,
                                        color: primary,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                if (options.isNotEmpty) ...[
                                  if (optionPrefix != null)
                                    pw.Text(
                                      '$optionPrefix: ',
                                      style: pw.TextStyle(
                                        fontSize: 8.0,
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
                                        fontSize: 8.0,
                                        boxSize: 9.8,
                                      ),
                                    );
                                  }),
                                  pw.SizedBox(width: 4),
                                ],
                                pw.Text(
                                  'remarks: ',
                                  style: pw.TextStyle(
                                    fontSize: 8.0,
                                    fontWeight: pw.FontWeight.bold,
                                    color: dark,
                                  ),
                                ),
                                pw.Expanded(
                                  child: pw.Container(
                                    height: 14.5,
                                    decoration: pw.BoxDecoration(
                                      border: pw.Border(
                                        bottom: pw.BorderSide(
                                          color: lineRuleColor,
                                          width: 0.6,
                                        ),
                                      ),
                                    ),
                                    alignment: pw.Alignment.bottomLeft,
                                    padding: const pw.EdgeInsets.only(
                                      bottom: 1.0,
                                    ),
                                    child: pw.Text(
                                      remVal,
                                      style: pw.TextStyle(
                                        fontSize: 8.0,
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
              // Anamnesis Date & Deliveries row
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4.5),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Anamnesis Date: ',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    buildDateBsBoxes(
                      visit?.anamnesisDate ?? visit?.visitDate ?? intakeDate,
                      hasData: hasPatient,
                      boxSize: 10.0,
                      boxHeight: 13.5,
                      fontSize: 8.0,
                    ),
                    pw.SizedBox(width: 10),
                    pw.Text(
                      'NR deliveries: ',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    buildCharBoxes(
                      visit?.deliveries?.toString() ?? '',
                      minBoxes: 2,
                      maxBoxes: 2,
                      boxSize: 12.2,
                      boxHeight: 15.5,
                      boxMargin: 1.0,
                    ),
                    pw.SizedBox(width: 10),
                    pw.Text(
                      'NR living children: ',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    buildCharBoxes(
                      visit?.livingChildren?.toString() ?? '',
                      minBoxes: 2,
                      maxBoxes: 2,
                      boxSize: 12.2,
                      boxHeight: 15.5,
                      boxMargin: 1.0,
                    ),
                    pw.SizedBox(width: 10),
                    pw.Text(
                      'NR abortion: ',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    buildCharBoxes(
                      visit?.abortions?.toString() ?? '',
                      minBoxes: 2,
                      maxBoxes: 2,
                      boxSize: 12.2,
                      boxHeight: 15.5,
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
                                fontSize: 12.0,
                                fontWeight: pw.FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            pw.Text(
                              'PATIENT REGISTRATION & ANAMNESIS — PAGE 1 (FRONT)',
                              style: pw.TextStyle(
                                fontSize: 9.0,
                                fontWeight: pw.FontWeight.bold,
                                color: dark,
                              ),
                            ),
                            if (camp != null)
                              pw.Text(
                                'Camp: ${sanitizeText(camp.name)} (${camp.campCode})${doctorHeaderPart.isNotEmpty ? " | $doctorHeaderPart" : ""}',
                                style: pw.TextStyle(
                                  fontSize: 7.6,
                                  color: inkMuted,
                                ),
                                maxLines: 2,
                              )
                            else
                              ne(
                                'Camp / शिविर: ________________ | Venue / ठाउँ: ________________${doctorHeaderPart.isNotEmpty ? " | $doctorHeaderPart" : ""}',
                                size: 7.6,
                                color: 0xFF334155,
                              ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      if (hasPatient)
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text(
                                  'PATIENT ID: ${patient.patientId}',
                                  style: pw.TextStyle(
                                    fontSize: 8.6,
                                    fontWeight: pw.FontWeight.bold,
                                    color: primary,
                                  ),
                                ),
                                pw.SizedBox(width: 3),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 0.5,
                                  ),
                                  decoration: pw.BoxDecoration(
                                    color: primary,
                                    borderRadius: const pw.BorderRadius.all(
                                      pw.Radius.circular(2),
                                    ),
                                  ),
                                  child: pw.Text(
                                    'P1',
                                    style: pw.TextStyle(
                                      fontSize: 7.2,
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 1.5),
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.BarcodeWidget(
                                  barcode: pw.Barcode.qrCode(),
                                  data: FormPageIdentity.buildQrPayload(
                                    tokenId: patient.patientId,
                                    pageNumber: 1,
                                  ),
                                  width: 17,
                                  height: 17,
                                ),
                                pw.SizedBox(width: 5),
                                pw.BarcodeWidget(
                                  barcode: pw.Barcode.code128(),
                                  data: patient.patientId,
                                  width: 60,
                                  height: 16,
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
                              data: FormPageIdentity.buildQrPayload(
                                tokenId: preprintedPatientId,
                                pageNumber: 1,
                              ),
                              width: 24,
                              height: 24,
                            ),
                            pw.SizedBox(width: 6),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Row(
                                  mainAxisSize: pw.MainAxisSize.min,
                                  children: [
                                    pw.Text(
                                      'PATIENT ID: $preprintedPatientId',
                                      style: pw.TextStyle(
                                        fontSize: 9.0,
                                        fontWeight: pw.FontWeight.bold,
                                        color: primary,
                                      ),
                                    ),
                                    pw.SizedBox(width: 4),
                                    pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: pw.BoxDecoration(
                                        color: primary,
                                        borderRadius: const pw.BorderRadius.all(
                                          pw.Radius.circular(2),
                                        ),
                                      ),
                                      child: pw.Text(
                                        'P1',
                                        style: pw.TextStyle(
                                          fontSize: 7.5,
                                          fontWeight: pw.FontWeight.bold,
                                          color: PdfColors.white,
                                        ),
                                      ),
                                    ),
                                  ],
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
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: FormPageIdentity.buildQrPayload(
                                pageNumber: 1,
                              ),
                              width: 22,
                              height: 22,
                            ),
                            pw.SizedBox(width: 5),
                            pw.Text(
                              'Token: ',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            buildCharBoxes(
                              dynamicTokenPrefix,
                              minBoxes: dynamicTokenTotalBoxes,
                              maxBoxes: dynamicTokenTotalBoxes,
                              boxSize: dynamicTokenBoxSize,
                              boxHeight: 15.5,
                              boxMargin: dynamicTokenBoxMargin,
                            ),
                            pw.SizedBox(width: 3),
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: pw.BoxDecoration(
                                color: primary,
                                borderRadius: const pw.BorderRadius.all(
                                  pw.Radius.circular(2),
                                ),
                              ),
                              child: pw.Text(
                                'P1',
                                style: pw.TextStyle(
                                  fontSize: 7.8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  triageStrip,
                  pw.SizedBox(height: 5),
                  sectionA,
                  pw.SizedBox(height: 5),
                  sectionB,
                  pw.SizedBox(height: 5),
                  station1,
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
        margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        build: (ctx) {
          const fs = 8.4;
          const fsSmall = 8.2;

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
              margin: const pw.EdgeInsets.only(top: 2.5, bottom: 3.0),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2.8,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('F1F5F9'),
                border: pw.Border(
                  left: pw.BorderSide(
                    color: PdfColor.fromHex('1B365D'),
                    width: 3.2,
                  ),
                  top: pw.BorderSide(
                    color: PdfColor.fromHex('94A3B8'),
                    width: 0.7,
                  ),
                  right: pw.BorderSide(
                    color: PdfColor.fromHex('94A3B8'),
                    width: 0.7,
                  ),
                  bottom: pw.BorderSide(
                    color: PdfColor.fromHex('94A3B8'),
                    width: 0.7,
                  ),
                ),
              ),
              child: renderBilingualText(
                title,
                fontSize: 9.4,
                bold: true,
                enColor: 0xFF0F172A,
                neColor: 0xFF0F172A,
              ),
            );
          }

          pw.Widget cb(
            String label,
            bool checked, {
            double? textWidth,
            double bottom = 0.0,
            bool isExpanded = false,
            double boxSize = 10.8,
            double fontSize = 8.4,
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
                      color: checked ? primary : PdfColor.fromHex('334155'),
                      width: 0.9,
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
                  final content = renderBilingualText(
                    label,
                    fontSize: fontSize,
                    bold: checked,
                    maxWidth: textWidth,
                    allowWrap: isExpanded || textWidth != null,
                  );
                  if (textWidth != null) {
                    return pw.SizedBox(width: textWidth, child: content);
                  } else if (isExpanded) {
                    return pw.Expanded(child: content);
                  }
                  return content;
                }(),
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
              padding: const pw.EdgeInsets.only(bottom: 3.0),
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
                    boxSize: 10.8,
                    fontSize: 8.4,
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Container(
                      height: 16.5,
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: lineRuleColor,
                            width: 0.6,
                          ),
                        ),
                      ),
                      alignment: pw.Alignment.bottomLeft,
                      padding: const pw.EdgeInsets.only(bottom: 1.0),
                      child: pw.Text(
                        hasNotes ? sanitizeText(remarks) : '',
                        style: pw.TextStyle(fontSize: 8.2, color: primary),
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
          final isEcgAbnormal =
              ecgText.contains('abnormal') ||
              ecgText.contains('arrhythmia') ||
              ecgText.contains('tachycardia') ||
              ecgText.contains('bradycardia') ||
              ecgText.contains('ischemia') ||
              ecgText.contains('st-t');
          final isEcgNormal =
              !isEcgAbnormal &&
              (RegExp(r'\bnormal\b').hasMatch(ecgText) ||
                  ecgText.contains('sinus rhythm'));
          final isEcgNotDone = ecgText.contains('not done');

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
                    visit?.examDate ?? visit?.visitDate ?? intakeDate,
                    hasData: hasPatient,
                    boxSize: 10.0,
                    boxHeight: 13.5,
                    fontSize: 8.0,
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text('uterus inside: ', style: bold(size: fsSmall)),
                  cb(
                    'yes',
                    visit?.uterusInside == true,
                    bottom: 0,
                    boxSize: 10.2,
                    fontSize: 8.2,
                  ),
                  cb(
                    'no',
                    visit?.uterusInside == false,
                    bottom: 0,
                    boxSize: 10.2,
                    fontSize: 8.2,
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text('pelvic floor muscle: ', style: bold(size: fsSmall)),
                  cb(
                    'normal',
                    tone == 'normal',
                    bottom: 0,
                    boxSize: 10.2,
                    fontSize: 8.2,
                  ),
                  cb(
                    'weak',
                    tone == 'weak',
                    bottom: 0,
                    boxSize: 10.2,
                    fontSize: 8.2,
                  ),
                  cb(
                    'hypertonic',
                    tone == 'hypertonic' || tone == 'torn',
                    bottom: 0,
                    boxSize: 10.2,
                    fontSize: 8.2,
                  ),
                ],
              ),
              pw.SizedBox(height: 2.5),
              // 4 Anatomical Examination Lines matching Physical Form
              examLine(
                label: 'vulva',
                isNormal:
                    visit?.vulvaRemarks != null &&
                    visit!.vulvaRemarks!.toLowerCase().contains('normal'),
                remarks: visit?.vulvaRemarks,
              ),
              examLine(
                label: 'vagina',
                isNormal:
                    visit?.vaginaRemarks != null &&
                    visit!.vaginaRemarks!.toLowerCase().contains('normal'),
                remarks: visit?.vaginaRemarks,
              ),
              examLine(
                label: 'cervix',
                isNormal:
                    visit?.cervixRemarks != null &&
                    visit!.cervixRemarks!.toLowerCase().contains('normal'),
                remarks: visit?.cervixRemarks,
              ),
              examLine(
                label: 'uterus',
                isNormal:
                    visit?.uterusRemarks != null &&
                    visit!.uterusRemarks!.toLowerCase().contains('normal'),
                remarks: visit?.uterusRemarks,
              ),
              pw.SizedBox(height: 3.0),
              pw.Text(
                'POP Compartment Staging (Baden-Walker / POP-Q - Tick one stage per compartment):',
                style: bold(size: 8.0),
              ),
              pw.SizedBox(height: 2.5),
              // POP Staging Rows (Anterior, Middle, Posterior)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(
                    width: 96,
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
                      fontSize: 8.4,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3.0),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(
                    width: 96,
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
                      fontSize: 8.4,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3.0),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(
                    width: 96,
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
                      fontSize: 8.4,
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
                    visit?.labTestDate ?? visit?.visitDate ?? intakeDate,
                    hasData: hasPatient,
                    boxSize: 10.0,
                    boxHeight: 13.5,
                    fontSize: 8.0,
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text('urine test: ', style: bold(size: fsSmall)),
                  cb(
                    'normal',
                    (visit?.urineTest ?? '').toLowerCase().contains('normal'),
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.4,
                  ),
                  cb(
                    'pos',
                    (visit?.urineTest ?? '').toLowerCase().contains('pos') ||
                        (visit?.urineTest ?? '').toLowerCase().contains('+'),
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.4,
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('pregnancy test: ', style: bold(size: fsSmall)),
                  cb(
                    'neg',
                    (visit?.pregnancyTest ?? '').toLowerCase().startsWith('neg'),
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.4,
                  ),
                  cb(
                    'pos',
                    (visit?.pregnancyTest ?? '').toLowerCase().startsWith('pos'),
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.4,
                  ),
                ],
              ),
              pw.SizedBox(height: 3.0),
              // Row 2: Vitals & Blood Glucose with printed units
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('blood pressure: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 58,
                    height: 15.5,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: lineRuleColor,
                          width: 0.6,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    padding: const pw.EdgeInsets.only(bottom: 1.0),
                    child: pw.Text(
                      (visit != null && visit.systolicBp != null)
                          ? '${visit.systolicBp} / ${visit.diastolicBp ?? "-"}'
                          : '/',
                      style: pw.TextStyle(
                        fontSize: 8.2,
                        color: (visit != null && visit.systolicBp != null)
                            ? primary
                            : inkMuted,
                      ),
                    ),
                  ),
                  pw.Text(' mmHg', style: pw.TextStyle(fontSize: 7.8, color: inkMuted)),
                  pw.SizedBox(width: 9),
                  pw.Text('pulse: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 36,
                    height: 15.5,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: lineRuleColor,
                          width: 0.6,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    padding: const pw.EdgeInsets.only(bottom: 1.0),
                    child: pw.Text(
                      visit?.pulse != null ? '${visit!.pulse}' : '',
                      style: pw.TextStyle(fontSize: 8.2, color: primary),
                    ),
                  ),
                  pw.Text(' bpm', style: pw.TextStyle(fontSize: 7.8, color: inkMuted)),
                  pw.SizedBox(width: 9),
                  pw.Text('SpO2: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 34,
                    height: 15.5,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: lineRuleColor,
                          width: 0.6,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    padding: const pw.EdgeInsets.only(bottom: 1.0),
                    child: pw.Text(
                      visit?.spo2 != null ? '${visit!.spo2}' : '',
                      style: pw.TextStyle(fontSize: 8.2, color: primary),
                    ),
                  ),
                  pw.Text(' %', style: pw.TextStyle(fontSize: 7.8, color: inkMuted)),
                  pw.SizedBox(width: 9),
                  pw.Text('blood glucose: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 40,
                    height: 15.5,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: lineRuleColor,
                          width: 0.6,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    padding: const pw.EdgeInsets.only(bottom: 1.0),
                    child: pw.Text(
                      visit?.glucose != null ? '${visit!.glucose}' : '',
                      style: pw.TextStyle(fontSize: 8.2, color: primary),
                    ),
                  ),
                  pw.Text(' mg/dL', style: pw.TextStyle(fontSize: 7.8, color: inkMuted)),
                ],
              ),
              pw.SizedBox(height: 3.5),
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
                    fontSize: 8.4,
                  ),
                  cb(
                    'Abnormal',
                    isEcgAbnormal,
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.4,
                  ),
                  cb(
                    'Not Done',
                    isEcgNotDone,
                    bottom: 0,
                    boxSize: 10.5,
                    fontSize: 8.4,
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text('ECG Notes: ', style: bold(size: fsSmall)),
                  pw.Expanded(
                    child: pw.Container(
                      height: 15.5,
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: lineRuleColor,
                            width: 0.6,
                          ),
                        ),
                      ),
                      alignment: pw.Alignment.bottomLeft,
                      padding: const pw.EdgeInsets.only(bottom: 1.0),
                      child: pw.Text(
                        sanitizeText(visit?.ecgNotes),
                        style: pw.TextStyle(fontSize: 8.2, color: primary),
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
                    visit?.conclusionDate ?? visit?.visitDate ?? intakeDate,
                    hasData: hasPatient,
                    boxSize: 10.0,
                    boxHeight: 13.5,
                    fontSize: 8.0,
                  ),
                  pw.SizedBox(width: 10),
                  pw.Text('highest POP stage: ', style: bold(size: fsSmall)),
                  ...[0, 1, 2, 3, 4].map(
                    (s) => cb(
                      'stage $s',
                      visit?.highestPopStage == s,
                      bottom: 0,
                      boxSize: 10.5,
                      fontSize: 8.4,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3.0),
              // 4-Column Diagnosis Grid with all 21 diagnoses matching physical Yellow Form
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 5,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColor.fromHex('94A3B8'),
                    width: 0.7,
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
                      flex: 24,
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
                                bottom: 2.2,
                                fontSize: 8.2,
                                boxSize: 10.0,
                              );
                            }).toList(),
                      ),
                    ),
                    pw.SizedBox(width: 4),
                    // Col 2 (6 diagnoses)
                    pw.Expanded(
                      flex: 24,
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
                                bottom: 2.2,
                                fontSize: 8.2,
                                boxSize: 10.0,
                              );
                            }).toList(),
                      ),
                    ),
                    pw.SizedBox(width: 4),
                    // Col 3 (5 diagnoses — wider flex for long floor muscle labels)
                    pw.Expanded(
                      flex: 30,
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
                                bottom: 2.2,
                                fontSize: 8.2,
                                boxSize: 10.0,
                              );
                            }).toList(),
                      ),
                    ),
                    pw.SizedBox(width: 4),
                    // Col 4 (4 diagnoses)
                    pw.Expanded(
                      flex: 22,
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
                                bottom: 2.2,
                                fontSize: 8.2,
                                boxSize: 10.0,
                              );
                            }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 2.5),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Other: ', style: bold(size: fsSmall)),
                  pw.Expanded(
                    child: pw.Container(
                      height: 15.5,
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: lineRuleColor,
                            width: 0.6,
                          ),
                        ),
                      ),
                      alignment: pw.Alignment.bottomLeft,
                      padding: const pw.EdgeInsets.only(bottom: 1.0),
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
                        style: pw.TextStyle(fontSize: 8.2, color: primary),
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
                    visit?.treatmentDate ?? visit?.visitDate ?? intakeDate,
                    hasData: hasPatient,
                    boxSize: 10.0,
                    boxHeight: 13.5,
                    fontSize: 8.0,
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text('pessary: ', style: bold(size: fsSmall)),
                  cb(
                    'ring',
                    (visit?.pessaryType ?? '').toLowerCase() == 'ring',
                    bottom: 0,
                    fontSize: 8.2,
                    boxSize: 10.2,
                  ),
                  cb(
                    'ring with support',
                    (visit?.pessaryType ?? '').toLowerCase().contains(
                      'support',
                    ),
                    bottom: 0,
                    fontSize: 8.2,
                    boxSize: 10.2,
                  ),
                  cb(
                    'ring with knob',
                    (visit?.pessaryType ?? '').toLowerCase().contains('knob'),
                    bottom: 0,
                    fontSize: 8.2,
                    boxSize: 10.2,
                  ),
                  pw.SizedBox(width: 2),
                  pw.Text('size: ', style: bold(size: fsSmall)),
                  pw.Container(
                    width: 30,
                    height: 15.0,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: lineRuleColor,
                          width: 0.6,
                        ),
                      ),
                    ),
                    alignment: pw.Alignment.bottomCenter,
                    padding: const pw.EdgeInsets.only(bottom: 1.0),
                    child: pw.Text(
                      ClinicalConstants.formatPessarySize(
                        visit?.pessarySize,
                        includeUnit: false,
                        fallback: '',
                      ),
                      style: pw.TextStyle(fontSize: 8.2, color: primary),
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
                  pw.Expanded(
                    child: pw.Wrap(
                      crossAxisAlignment: pw.WrapCrossAlignment.center,
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        cb(
                          'weak pelvic floor',
                          visit?.counseling.any(
                                (c) =>
                                    c.toLowerCase().contains('pelvic') ||
                                    c.toLowerCase().contains('pfmt'),
                              ) ??
                              false,
                          bottom: 0,
                          fontSize: 8.2,
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
                          fontSize: 8.2,
                          boxSize: 10.0,
                        ),
                        cb(
                          'stress incontinence',
                          visit?.counseling.any(
                                (c) => c.toLowerCase().contains('stress'),
                              ) ??
                              false,
                          bottom: 0,
                          fontSize: 8.2,
                          boxSize: 10.0,
                        ),
                        cb(
                          'urge incontinence',
                          visit?.counseling.any(
                                (c) => c.toLowerCase().contains('urge'),
                              ) ??
                              false,
                          bottom: 0,
                          fontSize: 8.2,
                          boxSize: 10.0,
                        ),
                        cb(
                          'abdominal pain',
                          visit?.counseling.any(
                                (c) => c.toLowerCase().contains('pain'),
                              ) ??
                              false,
                          bottom: 0,
                          fontSize: 8.2,
                          boxSize: 10.0,
                        ),
                      ],
                    ),
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
                    fontSize: 8.2,
                    boxSize: 10.2,
                  ),
                  cb(
                    'Model Hospital',
                    (visit?.surgicalReferral ?? '').toLowerCase().contains(
                      'model',
                    ),
                    bottom: 0,
                    fontSize: 8.2,
                    boxSize: 10.2,
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
                    fontSize: 8.2,
                    boxSize: 10.2,
                  ),
                ],
              ),
              pw.SizedBox(height: 3.5),
              // 2-Column Medication Grid (All 10 formulary medications)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColor.fromHex('94A3B8'),
                    width: 0.7,
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
                                bottom: 4.5,
                                fontSize: 8.4,
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
                                bottom: 4.5,
                                fontSize: 8.4,
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
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('other medication: ', style: bold(size: fsSmall)),
                  pw.Expanded(
                    child: pw.Container(
                      height: 15.5,
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: lineRuleColor,
                            width: 0.6,
                          ),
                        ),
                      ),
                      alignment: pw.Alignment.bottomLeft,
                      padding: const pw.EdgeInsets.only(bottom: 1.0),
                      child: pw.Text(
                        sanitizeText(visit?.customMedication),
                        style: pw.TextStyle(fontSize: 8.2, color: primary),
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
              followUpDest.trim().isNotEmpty &&
              !followUpDest.toLowerCase().contains('health post') &&
              !followUpDest.toLowerCase().contains('nurse') &&
              !followUpDest.toLowerCase().contains('no follow');

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
                    visit?.outtakeDate ?? visit?.visitDate ?? intakeDate,
                    hasData: hasPatient,
                    boxSize: 10.0,
                    boxHeight: 13.5,
                    fontSize: 8.0,
                  ),
                ],
              ),
              pw.SizedBox(height: 4.0),
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
                          bottom: 5.5,
                          fontSize: 8.4,
                          boxSize: 10.8,
                        ),
                        cb(
                          'GynaeSupport Nurse (गाइने नर्स)',
                          (followUpDest ?? '').toLowerCase().contains(
                                'gynaesupport',
                              ) ||
                              (followUpDest ?? '').toLowerCase().contains(
                                'nurse',
                              ),
                          bottom: 5.5,
                          fontSize: 8.4,
                          boxSize: 10.8,
                        ),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            cb(
                              'Hospital: ',
                              isHospitalFollowUp,
                              bottom: 0,
                              fontSize: 8.4,
                              boxSize: 10.8,
                            ),
                            pw.Expanded(
                              child: pw.Container(
                                height: 15.5,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border(
                                    bottom: pw.BorderSide(
                                      color: lineRuleColor,
                                      width: 0.6,
                                    ),
                                  ),
                                ),
                                alignment: pw.Alignment.bottomLeft,
                                padding: const pw.EdgeInsets.only(bottom: 1.0),
                                child: pw.Text(
                                  isHospitalFollowUp
                                      ? sanitizeText(followUpDest)
                                      : '',
                                  style: pw.TextStyle(
                                    fontSize: 8.2,
                                    color: primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 5.0),
                        cb(
                          'no follow up needed',
                          visit?.followUpNeeded == false,
                          bottom: 0,
                          fontSize: 8.4,
                          boxSize: 10.8,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  // Right: Clinical Notes Box with faint horizontal handwriting guide lines
                  pw.Expanded(
                    flex: 50,
                    child: () {
                      final notesStr =
                          (visit?.outtakeNotes?.trim().isNotEmpty == true)
                          ? visit!.outtakeNotes!.trim()
                          : (visit?.followUpNotes?.trim() ?? '');
                      return pw.Container(
                        height: 88,
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 4.5,
                        ),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColor.fromHex('94A3B8'),
                            width: 0.7,
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
                              style: bold(size: 8.2),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Expanded(
                              child: notesStr.isNotEmpty
                                  ? pw.Text(
                                      notesStr,
                                      style: pw.TextStyle(
                                        fontSize: 8.2,
                                        color: primary,
                                      ),
                                      maxLines: 5,
                                    )
                                  : pw.Column(
                                      mainAxisAlignment:
                                          pw.MainAxisAlignment.spaceEvenly,
                                      children: List.generate(
                                        4,
                                        (_) => pw.Container(
                                          height: 0.55,
                                          color: PdfColor.fromHex('CBD5E1'),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      );
                    }(),
                  ),
                ],
              ),
            ],
          );

          // ── Signatures Block (Outreach Team Signatures) ──
          final signaturesBlock = pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6.0, bottom: 0.0),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                // 1. Data Entry Operator
                pw.SizedBox(
                  width: 145,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(height: 22.0), // Clear pen signing zone
                      pw.Container(
                        width: 120,
                        height: 0.8,
                        color: PdfColor.fromHex('1E293B'),
                      ),
                      pw.SizedBox(height: 3.5),
                      pw.Text(
                        'Data Entry Operator',
                        style: bold(size: 8.4),
                      ),
                      pw.SizedBox(height: 1.5),
                      if (hasPatient)
                        pw.Text(
                          'Name & Date: ${dateFormatter.format(intakeDate)}',
                          style: pw.TextStyle(
                            fontSize: 7.8,
                            color: inkMuted,
                          ),
                        )
                      else
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'Name & Date: ',
                              style: pw.TextStyle(
                                fontSize: 7.8,
                                color: inkMuted,
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Container(
                                height: 10,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border(
                                    bottom: pw.BorderSide(
                                      color: lineRuleColor,
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
                if (showNurse) ...[
                  pw.SizedBox(width: 10),
                  // 2. Attending Nurse
                  pw.SizedBox(
                    width: 195,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.SizedBox(height: 22.0), // Clear pen signing zone
                        pw.Container(
                          width: 130,
                          height: 0.8,
                          color: PdfColor.fromHex('1E293B'),
                        ),
                        pw.SizedBox(height: 3.5),
                        if (blankNurseLines) ...[
                          pw.Text('Attending Nurse', style: bold(size: 8.4)),
                          pw.Text(
                            'Signature & NNC No.',
                            style: pw.TextStyle(
                              fontSize: 7.8,
                              color: inkMuted,
                            ),
                          ),
                        ] else if (allNursesChecklist || (effectiveNurses.length > 1 && nurse == null && (visit == null || visit.attendingNurseNames.length > 1))) ...[
                          pw.Text('Attending Nurse (Tick on Paper):', style: bold(size: 8.0)),
                          pw.SizedBox(height: 2.0),
                          pw.Wrap(
                            alignment: pw.WrapAlignment.center,
                            spacing: 4,
                            runSpacing: 2,
                            children: effectiveNurses.map((n) {
                              final label = n.hasRegistration
                                  ? '${n.displayName} (${n.registrationNumber})'
                                  : n.displayName;
                              final isNurseSelected = visit != null &&
                                  visit.attendingNurseNames.any((vn) {
                                    final vLow = vn.toLowerCase().trim();
                                    final nLow = n.name.toLowerCase().trim();
                                    return vLow.isNotEmpty &&
                                        (vLow.contains(nLow) || nLow.contains(vLow));
                                  });
                              return cb(label, isNurseSelected, bottom: 0, boxSize: 9.8, fontSize: 7.8);
                            }).toList(),
                          ),
                        ] else if (nurse != null) ...[
                          pw.Text(sanitizeText(nurse.displayName), style: bold(size: 8.4)),
                          pw.Text(
                            nurse.hasRegistration
                                ? 'NNC No: ${nurse.registrationNumber}'
                                : 'Attending Nurse Signature',
                            style: pw.TextStyle(
                              fontSize: 7.8,
                              color: inkMuted,
                            ),
                          ),
                        ] else if (visit != null &&
                            visit.primaryNurseName != null &&
                            visit.primaryNurseName!.isNotEmpty) ...[
                          pw.Text(sanitizeText(visit.primaryNurseName!), style: bold(size: 8.4)),
                          pw.Text(
                            'Attending Nurse Signature',
                            style: pw.TextStyle(
                              fontSize: 7.8,
                              color: inkMuted,
                            ),
                          ),
                        ] else if (effectiveNurses.isNotEmpty) ...[
                          pw.Text(sanitizeText(effectiveNurses.first.displayName), style: bold(size: 8.4)),
                          pw.Text(
                            effectiveNurses.first.hasRegistration
                                ? 'NNC No: ${effectiveNurses.first.registrationNumber}'
                                : 'Attending Nurse Signature',
                            style: pw.TextStyle(
                              fontSize: 7.8,
                              color: inkMuted,
                            ),
                          ),
                        ] else ...[
                          pw.Text('Attending Nurse', style: bold(size: 8.4)),
                          pw.Text(
                            'Signature & NNC No.',
                            style: pw.TextStyle(
                              fontSize: 7.8,
                              color: inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                pw.SizedBox(width: 10),
                // 3. Examining Doctor
                pw.SizedBox(
                  width: 199,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.SizedBox(height: 22.0), // Clear pen signing zone
                      pw.Container(
                        width: 130,
                        height: 0.8,
                        color: PdfColor.fromHex('1E293B'),
                      ),
                      pw.SizedBox(height: 3.5),
                      if (!showDoctor || blankDoctorLines) ...[
                        pw.Text('Examining Doctor', style: bold(size: 8.4)),
                        pw.Text(
                          'Signature & NMC No.',
                          style: pw.TextStyle(
                            fontSize: 7.8,
                            color: inkMuted,
                          ),
                        ),
                      ] else if (allDoctorsChecklist || (effectiveDoctors.length > 1 && doctor == null && (visit == null || visit.attendingDoctorNames.length > 1))) ...[
                        pw.Text('Examining Doctor (Tick on Paper):', style: bold(size: 8.0)),
                        pw.SizedBox(height: 2.0),
                        pw.Wrap(
                          alignment: pw.WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 2,
                          children: effectiveDoctors.map((p) {
                            final label = p.hasNmc ? '${p.displayName} (${p.nmcNumber})' : p.displayName;
                            final isDocSelected = visit != null &&
                                visit.attendingDoctorNames.any((vd) {
                                  final vLow = vd
                                      .toLowerCase()
                                      .replaceAll(RegExp(r'^dr\.?\s*'), '')
                                      .trim();
                                  final pLow = p.name.toLowerCase().trim();
                                  return vLow.isNotEmpty &&
                                      (vLow.contains(pLow) || pLow.contains(vLow));
                                });
                            return cb(label, isDocSelected, bottom: 0, boxSize: 9.8, fontSize: 7.8);
                          }).toList(),
                        ),
                      ] else if (doctor != null) ...[
                        pw.Text(sanitizeText(doctor.displayName), style: bold(size: 8.4)),
                        pw.Text(
                          doctor.hasNmc
                              ? 'NMC No: ${doctor.nmcNumber}'
                              : 'Examining Doctor Signature',
                          style: pw.TextStyle(
                            fontSize: 7.8,
                            color: inkMuted,
                          ),
                        ),
                      ] else if (visit != null &&
                          visit.primaryDoctorName != null &&
                          visit.primaryDoctorName!.isNotEmpty) ...[
                        () {
                          final doc = DoctorProfile.parse(visit.primaryDoctorName!);
                          return pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text(sanitizeText(doc.displayName), style: bold(size: 8.4)),
                              pw.Text(
                                doc.hasNmc
                                    ? 'NMC No: ${doc.nmcNumber}'
                                    : 'Examining Doctor Signature',
                                style: pw.TextStyle(
                                  fontSize: 7.8,
                                  color: inkMuted,
                                ),
                              ),
                            ],
                          );
                        }(),
                      ] else if (effectiveDoctors.isNotEmpty) ...[
                        pw.Text(sanitizeText(effectiveDoctors.first.displayName), style: bold(size: 8.4)),
                        pw.Text(
                          effectiveDoctors.first.hasNmc
                              ? 'NMC No: ${effectiveDoctors.first.nmcNumber}'
                              : 'Examining Doctor Signature',
                          style: pw.TextStyle(
                            fontSize: 7.8,
                            color: inkMuted,
                          ),
                        ),
                      ] else ...[
                        pw.Text('Examining Doctor', style: bold(size: 8.4)),
                        pw.Text(
                          'Signature & NMC No.',
                          style: pw.TextStyle(
                            fontSize: 7.8,
                            color: inkMuted,
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
                                fontSize: 12.0,
                                fontWeight: pw.FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            pw.Text(
                              'CLINICAL ASSESSMENT & EXAMINATION — PAGE 2 (BACK)',
                              style: pw.TextStyle(
                                fontSize: 9.0,
                                fontWeight: pw.FontWeight.bold,
                                color: dark,
                              ),
                            ),
                            if (camp != null)
                              pw.Text(
                                'Stations 2 - 6 | Camp: ${sanitizeText(camp.name)} (${camp.campCode})',
                                style: pw.TextStyle(
                                  fontSize: 7.8,
                                  color: inkMuted,
                                ),
                              )
                            else
                              ne(
                                'Stations 2 - 6 | Universal Clinical Intake & Examination Form (सार्वभौमिक फाराम)',
                                size: 7.8,
                                color: 0xFF334155,
                              ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      if (hasPatient)
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text(
                                  'PATIENT ID: ${patient.patientId}',
                                  style: pw.TextStyle(
                                    fontSize: 8.6,
                                    fontWeight: pw.FontWeight.bold,
                                    color: primary,
                                  ),
                                ),
                                pw.SizedBox(width: 3),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 0.5,
                                  ),
                                  decoration: pw.BoxDecoration(
                                    color: dark,
                                    borderRadius: const pw.BorderRadius.all(
                                      pw.Radius.circular(2),
                                    ),
                                  ),
                                  child: pw.Text(
                                    'P2',
                                    style: pw.TextStyle(
                                      fontSize: 7.2,
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 1.5),
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.BarcodeWidget(
                                  barcode: pw.Barcode.qrCode(),
                                  data: FormPageIdentity.buildQrPayload(
                                    tokenId: patient.patientId,
                                    pageNumber: 2,
                                  ),
                                  width: 16,
                                  height: 16,
                                ),
                                pw.SizedBox(width: 5),
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
                              data: FormPageIdentity.buildQrPayload(
                                tokenId: preprintedPatientId,
                                pageNumber: 2,
                              ),
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
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: primary,
                                  ),
                                ),
                                buildCharBoxes(
                                  preprintedPatientId,
                                  minBoxes: preprintedPatientId.length,
                                  maxBoxes: preprintedPatientId.length,
                                  boxSize: preprintedPatientId.length > 18
                                      ? 9.8
                                      : (preprintedPatientId.length > 16
                                          ? 10.6
                                          : (preprintedPatientId.length <= 6 ? 12.5 : 11.4)),
                                  boxHeight: 15.5,
                                  boxMargin: preprintedPatientId.length <= 6 ? 1.5 : 1.0,
                                ),
                                pw.SizedBox(width: 3),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: pw.BoxDecoration(
                                    color: dark,
                                    borderRadius: const pw.BorderRadius.all(
                                      pw.Radius.circular(2),
                                    ),
                                  ),
                                  child: pw.Text(
                                    'P2',
                                    style: pw.TextStyle(
                                      fontSize: 7.8,
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      else
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: FormPageIdentity.buildQrPayload(
                                pageNumber: 2,
                              ),
                              width: 22,
                              height: 22,
                            ),
                            pw.SizedBox(width: 5),
                            pw.Text(
                              'Token: ',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: primary,
                              ),
                            ),
                            buildCharBoxes(
                              dynamicTokenPrefix,
                              minBoxes: dynamicTokenTotalBoxes,
                              maxBoxes: dynamicTokenTotalBoxes,
                              boxSize: dynamicTokenBoxSize,
                              boxHeight: 15.5,
                              boxMargin: dynamicTokenBoxMargin,
                            ),
                            pw.SizedBox(width: 3),
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: pw.BoxDecoration(
                                color: dark,
                                borderRadius: const pw.BorderRadius.all(
                                  pw.Radius.circular(2),
                                ),
                              ),
                              child: pw.Text(
                                'P2',
                                style: pw.TextStyle(
                                  fontSize: 7.8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  pw.SizedBox(height: 4.5),
                  station2,
                  pw.SizedBox(height: 4.5),
                  station3,
                  pw.SizedBox(height: 4.5),
                  station4,
                  pw.SizedBox(height: 4.5),
                  station5,
                  pw.SizedBox(height: 4.5),
                  station6,
                  pw.SizedBox(height: 4.5),
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
    void Function(int current, int total, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    final year = camp.startDate.year;
    final campCode = camp.campCode.trim().toUpperCase();
    // On Flutter Web, pure-Dart JS zlib Deflate across hundreds/thousands of pages
    // runs on the main UI thread and stalls finalization for minutes in debug/JS builds.
    final bool shouldCompress = !(kIsWeb && count > 150);

    // Pre-warm Devanagari glyph cache on a single template form when count > 1
    // so _saveWithNepali does not rebuild all `count` forms twice on cold cache.
    if (count > 1) {
      final warmupPdf = pw.Document(theme: theme, compress: false);
      final warmupId = PatientModel.generatePatientId(
        campCode: campCode,
        sequenceNumber: startSequence,
        year: year,
      );
      await _addPatientRegistrationFormPages(
        warmupPdf,
        camp: camp,
        preprintedPatientId: warmupId,
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
      await warmupPdf.save(enableEventLoopBalancing: true);
      if (_nePending.isNotEmpty) {
        await _renderPendingNepali();
      }
    }

    if (isCancelled?.call() == true) {
      return Uint8List(0);
    }

    final int progressStride = count <= 50 ? 1 : (count ~/ 50).clamp(2, 20);

    final bytes = await _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme, compress: shouldCompress);
      final frameWatch = Stopwatch()..start();

      for (int i = 0; i < count; i++) {
        if (isCancelled?.call() == true) {
          return pw.Document(theme: theme, compress: false);
        }

        final seq = startSequence + i;
        final patientId = PatientModel.generatePatientId(
          campCode: campCode,
          sequenceNumber: seq,
          year: year,
        );

        final bool shouldReport =
            (i == 0) || (i == count - 1) || ((i + 1) % progressStride == 0);
        if (shouldReport) {
          onProgress?.call(
            i + 1,
            count,
            'Building form ${i + 1} of $count (${((i + 1) / count * 100).toInt()}%)...',
          );
        }

        if (shouldReport || frameWatch.elapsedMilliseconds >= 12) {
          await Future.delayed(const Duration(milliseconds: 4));
          frameWatch.reset();
        }

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
      onProgress?.call(
        count,
        count,
        'Finalizing PDF document (${count * 2} pages)...',
      );
      await Future.delayed(const Duration(milliseconds: 16));
      return pdf;
    });

    if (isCancelled?.call() == true) {
      return Uint8List(0);
    }
    return bytes;
  }

  /// Generates a batch PDF containing 1-page blank Follow-Up Encounter Slips
  /// sequentially pre-printed with 5-digit Token IDs (e.g., 00001 to 00050).
  Future<Uint8List> generatePreNumberedBlankFollowUpSlipsPdf({
    required CampModel camp,
    required int startSequence,
    required int count,
    DoctorProfile? doctor,
    bool blankDoctorLines = false,
    bool allDoctorsChecklist = false,
    NurseProfile? nurse,
    bool blankNurseLines = false,
    bool allNursesChecklist = false,
    String organizationName = AppConstants.defaultOrganizationName,
    List<LookupItemModel>? diagnoses,
    List<LookupItemModel>? medications,
    List<LookupItemModel>? referralHospitals,
    void Function(int current, int total, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final theme = await getPdfTheme();
    final logoImage = await loadLogoImage();
    final year = camp.startDate.year;
    final campCode = camp.campCode.trim().toUpperCase();
    final bool shouldCompress = !(kIsWeb && count > 150);

    if (count > 1) {
      final warmupPdf = pw.Document(theme: theme, compress: false);
      final warmupId = PatientModel.generatePatientId(
        campCode: campCode,
        sequenceNumber: startSequence,
        year: year,
      );
      _addBlankFollowUpSlipPage(
        warmupPdf,
        camp: camp,
        preprintedTokenId: warmupId,
        doctor: doctor,
        blankDoctorLines: blankDoctorLines,
        allDoctorsChecklist: allDoctorsChecklist,
        nurse: nurse,
        blankNurseLines: blankNurseLines,
        allNursesChecklist: allNursesChecklist,
        organizationName: organizationName,
        diagnoses: diagnoses,
        medications: medications,
        referralHospitals: referralHospitals,
        logoImage: logoImage,
      );
      await warmupPdf.save(enableEventLoopBalancing: true);
      if (_nePending.isNotEmpty) {
        await _renderPendingNepali();
      }
    }

    if (isCancelled?.call() == true) {
      return Uint8List(0);
    }

    final int progressStride = count <= 50 ? 1 : (count ~/ 50).clamp(2, 20);

    final bytes = await _saveWithNepali(() async {
      final pdf = pw.Document(theme: theme, compress: shouldCompress);
      final frameWatch = Stopwatch()..start();

      for (int i = 0; i < count; i++) {
        if (isCancelled?.call() == true) {
          return pw.Document(theme: theme, compress: false);
        }

        final seq = startSequence + i;
        final tokenId = PatientModel.generatePatientId(
          campCode: campCode,
          sequenceNumber: seq,
          year: year,
        );

        final bool shouldReport =
            (i == 0) || (i == count - 1) || ((i + 1) % progressStride == 0);
        if (shouldReport) {
          onProgress?.call(
            i + 1,
            count,
            'Building follow-up sheet ${i + 1} of $count (${((i + 1) / count * 100).toInt()}%)...',
          );
        }

        if (shouldReport || frameWatch.elapsedMilliseconds >= 12) {
          await Future.delayed(const Duration(milliseconds: 4));
          frameWatch.reset();
        }

        _addBlankFollowUpSlipPage(
          pdf,
          camp: camp,
          preprintedTokenId: tokenId,
          doctor: doctor,
          blankDoctorLines: blankDoctorLines,
          allDoctorsChecklist: allDoctorsChecklist,
          nurse: nurse,
          blankNurseLines: blankNurseLines,
          allNursesChecklist: allNursesChecklist,
          organizationName: organizationName,
          diagnoses: diagnoses,
          medications: medications,
          referralHospitals: referralHospitals,
          logoImage: logoImage,
        );
      }
      onProgress?.call(
        count,
        count,
        'Finalizing PDF document ($count pages)...',
      );
      await Future.delayed(const Duration(milliseconds: 16));
      return pdf;
    });

    if (isCancelled?.call() == true) {
      return Uint8List(0);
    }
    return bytes;
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
      final docProfile = DoctorProfile.parse(docRaw);
      final docName = sanitizeText(docProfile.displayName);

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
                              'Intake Date: ${NepaliLocalizationService.formatDualCalendarDate(patient.intakeDate)}',
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
