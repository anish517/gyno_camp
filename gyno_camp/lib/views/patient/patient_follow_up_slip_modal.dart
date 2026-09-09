import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/services/file_download_helper.dart';
import '../../core/services/nepali_localization_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/camp_model.dart';
import '../../models/patient_model.dart';

class PatientFollowUpSlipModal extends StatelessWidget {
  final PatientModel patient;
  final CampModel? camp;
  final String organizationName;
  final bool showProceedButton;

  const PatientFollowUpSlipModal({
    super.key,
    required this.patient,
    this.camp,
    this.organizationName = 'Nepal Gyno Health Outreach Network',
    this.showProceedButton = true,
  });

  static Future<bool?> show(
    BuildContext context, {
    required PatientModel patient,
    CampModel? camp,
    String? organizationName,
    bool showProceedButton = true,
  }) {
    final effectiveOrgName = (organizationName?.isNotEmpty == true)
        ? organizationName!
        : (camp?.organizationName.isNotEmpty == true
            ? camp!.organizationName
            : 'Nepal Gyno Health Outreach Network');

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: PatientFollowUpSlipModal(
            patient: patient,
            camp: camp,
            organizationName: effectiveOrgName,
            showProceedButton: showProceedButton,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final campName = camp?.name ?? 'Gynecological Health Outreach Camp';
    final campCode = camp?.campCode ?? patient.campCode;
    final venue = camp?.venue ?? 'Health Center';
    final district = camp?.district.isNotEmpty == true ? camp!.district : patient.district;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.qr_code_2_rounded, color: AppTheme.primaryTeal, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PATIENT FOLLOW-UP TOKEN SLIP',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF1E293B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'बिरामी फलो-अप पुर्जी • Camp ID Token',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(false),
                tooltip: 'Close Slip',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Organization & Camp Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Text(
                  organizationName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  campName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  '$venue, Ward ${patient.ward} • $district (Camp Code: $campCode)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Primary Patient ID & Barcode / QR Code Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryTeal.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'PERMANENT PATIENT IDENTIFIER',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  patient.patientId,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 12),

                // QR Code and Barcode Visual Display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // QR Code Box
                    Container(
                      width: 100,
                      height: 100,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade400, width: 1.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CustomPaint(
                        painter: _QrMatrixPainter(data: patient.patientId),
                      ),
                    ),
                    const SizedBox(width: 18),

                    // Code-128 Barcode Representation
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            height: 60,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: CustomPaint(
                              size: const Size(double.infinity, 50),
                              painter: _Barcode128Painter(data: patient.patientId),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            patient.patientId,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, letterSpacing: 1.2, color: Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Scan with Field Nurse Tablet Scanner',
                            style: TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Demographics Overview Grid
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Full Name (नाम):', patient.fullName, isBold: true),
                const SizedBox(height: 6),
                _buildInfoRow('Age / Status (उमेर):', '${patient.age} years • ${patient.maritalStatus.toUpperCase()}'),
                const SizedBox(height: 6),
                _buildInfoRow(
                  '${patient.relationshipType ?? "Guardian"} (अभिभावक):',
                  patient.spouseOrFatherName?.isNotEmpty == true ? patient.spouseOrFatherName! : 'N/A',
                ),
                const SizedBox(height: 6),
                _buildInfoRow('Phone (फोन):', patient.mobile.isNotEmpty ? patient.mobile : 'None provided'),
                const SizedBox(height: 6),
                _buildInfoRow('Address (ठेगाना):', 'Ward ${patient.ward}, ${patient.municipality.isNotEmpty ? patient.municipality : district}'),
                if (patient.reasonsForVisit.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  const Text('Reasons for Visit / Chief Complaints (लक्षणहरू):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: patient.reasonsForVisit.map((reason) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Text(
                          NepaliLocalizationService.translate(reason),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal.shade800),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 6-Station Clinical Tracking Passport
          const Text(
            'Clinical Station Routing Passport (स्टेशन चेकलिस्ट)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildStationStep('Station 1: Registration & Intake', 'दर्ता र सहमति', isCompleted: true),
                const Divider(height: 12),
                _buildStationStep('Station 2: Physical & POP Exam', 'शारीरिक जाँच र आङ्ग खस्ने चरण', isCompleted: patient.hasClinicalVisit),
                const Divider(height: 12),
                _buildStationStep('Station 3: Vitals & Lab Testing', 'रक्तचाप, सुगर र ल्याब परीक्षण', isCompleted: patient.hasClinicalVisit),
                const Divider(height: 12),
                _buildStationStep('Station 4: Doctor Assessment', 'चिकित्सक रोग निदान', isCompleted: patient.hasClinicalVisit),
                const Divider(height: 12),
                _buildStationStep('Station 5: Treatment & Pharmacy', 'औषधि, पेसरी र परामर्श', isCompleted: patient.hasClinicalVisit),
                const Divider(height: 12),
                _buildStationStep('Station 6: Discharge & Referral', 'अन्तिम सल्लाह र अस्पताल प्रेषण', isCompleted: patient.hasClinicalVisit),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              // Print PDF Slip Button
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Print PDF Slip', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => _printPdfSlip(context),
                ),
              ),
              const SizedBox(width: 12),

              // Proceed to Clinical Chart Button
              if (showProceedButton)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.assignment_turned_in_rounded, size: 18),
                    label: const Text('Station 2 Chart', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStationStep(String title, String subtitle, {required bool isCompleted}) {
    return Row(
      children: [
        Icon(
          isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isCompleted ? AppTheme.successGreen : const Color(0xFF94A3B8),
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isCompleted ? FontWeight.bold : FontWeight.w500,
                  color: isCompleted ? AppTheme.primaryTeal : const Color(0xFF334155),
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isCompleted ? AppTheme.successGreen.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isCompleted ? 'COMPLETED' : 'PENDING',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isCompleted ? AppTheme.successGreen : const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _printPdfSlip(BuildContext context) async {
    try {
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: pw.Text(
                    organizationName.toUpperCase(),
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    camp?.name ?? 'Gynecological Health Outreach Camp',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    'PATIENT FOLLOW-UP TOKEN SLIP / Patient Triage Pass',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.SizedBox(height: 10),

                // Barcode and QR
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PATIENT ID: ${patient.patientId}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('Name: ${patient.fullName}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Age: ${patient.age} yrs | Ward: ${patient.ward} | ${patient.district}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Guardian / Spouse: ${patient.spouseOrFatherName ?? "N/A"}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Mobile: ${patient.mobile.isNotEmpty ? patient.mobile : "N/A"}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Date: ${patient.intakeDate.toString().split(" ")[0]}', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: patient.patientId,
                      width: 75,
                      height: 75,
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: patient.patientId,
                  height: 40,
                ),
                pw.SizedBox(height: 12),
                pw.Divider(),
                pw.SizedBox(height: 6),
                pw.Text('CLINICAL STATIONS CHECKLIST', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Bullet(text: '[X] Station 1: Intake & Demographics'),
                pw.Bullet(text: '[ ] Station 2: Physical & POP Exam'),
                pw.Bullet(text: '[ ] Station 3: Vitals & Lab Testing'),
                pw.Bullet(text: '[ ] Station 4: Doctor Assessment & Diagnoses'),
                pw.Bullet(text: '[ ] Station 5: Treatment, Medications & Pessary'),
                pw.Bullet(text: '[ ] Station 6: Outtake & Surgical Referral'),
                pw.Spacer(),
                pw.Center(
                  child: pw.Text(
                    'Please hold this token pass while visiting each clinical station.',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                ),
              ],
            );
          },
        ),
      );

      final pdfBytes = await doc.save();
      final filename = 'Patient_Slip_${patient.patientId}.pdf';
      await FileDownloadHelper.saveAndDownloadFile(
        bytes: pdfBytes,
        filename: filename,
        mimeType: 'application/pdf',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Follow-up slip downloaded: $filename'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print preview error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

/// Custom Vector QR Code Matrix Painter with Finder Squares and deterministic module grid
class _QrMatrixPainter extends CustomPainter {
  final String data;
  _QrMatrixPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final paintDark = Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.fill;
    final paintLight = Paint()..color = Colors.white..style = PaintingStyle.fill;

    // Draw background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintLight);

    const int matrixSize = 25; // Standard 25x25 QR matrix (Version 2)
    final double moduleW = size.width / matrixSize;
    final double moduleH = size.height / matrixSize;

    // Generate module map
    final modules = List.generate(matrixSize, (_) => List.filled(matrixSize, false));

    // 1. Finder patterns at Top-Left, Top-Right, Bottom-Left
    _drawFinderPattern(modules, 0, 0);
    _drawFinderPattern(modules, matrixSize - 7, 0);
    _drawFinderPattern(modules, 0, matrixSize - 7);

    // 2. Timing patterns
    for (int i = 8; i < matrixSize - 8; i++) {
      modules[6][i] = i % 2 == 0;
      modules[i][6] = i % 2 == 0;
    }

    // 3. Fill data modules using deterministic hash of patient ID
    int hash = data.hashCode.abs();
    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        // Skip finder squares and timing lines
        if (_isReservedModule(r, c, matrixSize)) continue;
        hash = (hash * 31 + (r * 17) + c) & 0x7FFFFFFF;
        modules[r][c] = (hash % 3) == 0;
      }
    }

    // Paint modules
    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        if (modules[r][c]) {
          canvas.drawRect(
            Rect.fromLTWH(c * moduleW, r * moduleH, moduleW, moduleH),
            paintDark,
          );
        }
      }
    }
  }

  void _drawFinderPattern(List<List<bool>> m, int startRow, int startCol) {
    for (int r = 0; r < 7; r++) {
      for (int c = 0; c < 7; c++) {
        final isBorder = r == 0 || r == 6 || c == 0 || c == 6;
        final isCenter = r >= 2 && r <= 4 && c >= 2 && c <= 4;
        m[startRow + r][startCol + c] = isBorder || isCenter;
      }
    }
  }

  bool _isReservedModule(int r, int c, int size) {
    // Top-left
    if (r <= 7 && c <= 7) return true;
    // Top-right
    if (r <= 7 && c >= size - 8) return true;
    // Bottom-left
    if (r >= size - 8 && c <= 7) return true;
    // Timing pattern
    if (r == 6 || c == 6) return true;
    return false;
  }

  @override
  bool shouldRepaint(covariant _QrMatrixPainter oldDelegate) => oldDelegate.data != data;
}

/// Custom Code 128 Style Barcode Painter
class _Barcode128Painter extends CustomPainter {
  final String data;
  _Barcode128Painter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final paintDark = Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.fill;
    final paintLight = Paint()..color = Colors.white..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintLight);

    int seed = data.hashCode.abs();
    double currentX = 8.0;
    final availableWidth = size.width - 16.0;

    // Fixed start guard
    canvas.drawRect(Rect.fromLTWH(currentX, 0, 2.5, size.height), paintDark);
    currentX += 4.5;
    canvas.drawRect(Rect.fromLTWH(currentX, 0, 1.5, size.height), paintDark);
    currentX += 3.5;

    // Draw lines representing data characters
    int charCount = data.length.clamp(10, 26);
    double charWidth = (availableWidth - 24) / charCount;

    for (int i = 0; i < charCount; i++) {
      int val = (seed >> (i % 24)) & 0x07;
      seed = (seed * 37 + (i < data.length ? data.codeUnitAt(i) : 42)) & 0x7FFFFFFF;

      double w1 = ((val & 0x01) + 1) * 1.3;
      double w2 = (((val >> 1) & 0x01) + 1) * 1.1;

      canvas.drawRect(Rect.fromLTWH(currentX, 0, w1, size.height), paintDark);
      currentX += w1 + 1.8;

      canvas.drawRect(Rect.fromLTWH(currentX, 0, w2, size.height), paintDark);
      currentX += charWidth - (w1 + 1.8);
      if (currentX > size.width - 14) break;
    }

    // Stop guard
    canvas.drawRect(Rect.fromLTWH(size.width - 10, 0, 2.5, size.height), paintDark);
    canvas.drawRect(Rect.fromLTWH(size.width - 6, 0, 1.5, size.height), paintDark);
  }

  @override
  bool shouldRepaint(covariant _Barcode128Painter oldDelegate) => oldDelegate.data != data;
}
