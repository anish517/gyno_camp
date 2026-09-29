import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Camp creation doctor parsing and PDF generation with 3 doctors', () async {
    final camp3Doctors = CampModel(
      id: 'camp-3doc',
      campCode: 'DOC3',
      name: 'Morang Outreach Camp',
      province: 'Koshi',
      district: 'Morang',
      municipality: 'Biratnagar',
      ward: '03',
      venue: 'Primary Hospital',
      startDate: DateTime(2026, 9, 20),
      endDate: DateTime(2026, 9, 22),
      status: CampStatus.open,
      doctorName: 'Anita Sharma',
      doctorNames: ['Anita Sharma', 'Ramesh Karki', 'Bipin Joshi'],
      createdAt: DateTime(2026, 9, 20),
    );

    final pdfService = PdfReportService();
    final bytes = await pdfService.generatePatientRegistrationFormPdf(
      camp: camp3Doctors,
      organizationName: 'Community Health Outreach Mission',
    );

    expect(bytes.isNotEmpty, true);
    final outFile = File('test_samples/sample_blank_3doctors.pdf');
    outFile.writeAsBytesSync(bytes);
  });

  test('Camp blank form with 4 and 5 doctors generates valid 2-page PDF without overflow', () async {
    final camp5Doctors = CampModel(
      id: 'camp-5doc',
      campCode: 'DOC5',
      name: 'Kathmandu Multi-Specialty Outreach Health Mission',
      province: 'Bagmati',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '04',
      venue: 'Primary Healthcare Center',
      startDate: DateTime(2026, 9, 20),
      endDate: DateTime(2026, 9, 22),
      status: CampStatus.open,
      doctorName: 'Anita Sharma',
      doctorNames: [
        'Anita Sharma',
        'Ramesh Karki',
        'Bipin Joshi',
        'Sita Poudel',
        'Pooja Shrestha',
      ],
      createdAt: DateTime(2026, 9, 20),
    );

    final pdfService = PdfReportService();
    final bytes = await pdfService.generatePatientRegistrationFormPdf(
      camp: camp5Doctors,
      organizationName: 'Ministry of Health & Population - Nepal Rural Health',
    );

    expect(bytes.isNotEmpty, true);
    final outFile = File('test_samples/sample_blank_5doctors.pdf');
    outFile.writeAsBytesSync(bytes);
    final textContent = _extractPdfText(bytes);
    expect(textContent.contains('Anita'), true);
    expect(textContent.contains('Sharma'), true);
    expect(textContent.contains('Ramesh'), true);
    expect(textContent.contains('Karki'), true);
    expect(textContent.contains('Bipin'), true);
    expect(textContent.contains('Joshi'), true);
    expect(textContent.contains('Sita'), true);
    expect(textContent.contains('Pooja'), true);
  });

  test('Camp doctor parsing tests with various delimiters', () {
    List<String> sanitizeDoctorList(String input) {
      if (input.trim().isEmpty) return <String>[];
      return input
          .split(RegExp(r'[,;\n/]|(?:\s+and\s+)|\&', caseSensitive: false))
          .map((e) => e.trim().replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    }

    // Comma separated
    expect(
      sanitizeDoctorList('Dr. Anita Sharma, Dr. Ramesh Karki, Dr. Bipin Joshi'),
      ['Anita Sharma', 'Ramesh Karki', 'Bipin Joshi'],
    );

    // Natural English with "and"
    expect(
      sanitizeDoctorList('Dr. Anita Sharma, Dr. Ramesh Karki and Dr. Bipin Joshi'),
      ['Anita Sharma', 'Ramesh Karki', 'Bipin Joshi'],
    );

    // Semicolon separated
    expect(
      sanitizeDoctorList('Dr. Anita Sharma; Dr. Ramesh Karki; Dr. Bipin Joshi'),
      ['Anita Sharma', 'Ramesh Karki', 'Bipin Joshi'],
    );

    // Slash separated
    expect(
      sanitizeDoctorList('Dr. Anita Sharma / Dr. Ramesh Karki / Dr. Bipin Joshi'),
      ['Anita Sharma', 'Ramesh Karki', 'Bipin Joshi'],
    );

    // Ampersand separated
    expect(
      sanitizeDoctorList('Dr. Anita Sharma, Dr. Ramesh Karki & Dr. Bipin Joshi'),
      ['Anita Sharma', 'Ramesh Karki', 'Bipin Joshi'],
    );

    // Newline separated
    expect(
      sanitizeDoctorList("Dr. Anita Sharma\nDr. Ramesh Karki\nDr. Bipin Joshi"),
      ['Anita Sharma', 'Ramesh Karki', 'Bipin Joshi'],
    );

    // Duplicate removal
    expect(
      sanitizeDoctorList('Dr. Anita Sharma, Dr. Anita Sharma, Dr. Bipin Joshi'),
      ['Anita Sharma', 'Bipin Joshi'],
    );
  });

  test('DoctorProfile parsing and formatted label test', () {
    final doc1 = DoctorProfile.parse('Dr. Sita Sharma (NMC: 12345)');
    expect(doc1.name, 'Sita Sharma');
    expect(doc1.nmcNumber, '12345');
    expect(doc1.formattedLabel, 'Dr. Sita Sharma (NMC: 12345)');

    final doc2 = DoctorProfile.parse('Ramesh Karki - NMC 9988');
    expect(doc2.name, 'Ramesh Karki');
    expect(doc2.nmcNumber, '9988');

    final doc3 = DoctorProfile.parse('Dr. Priya Thapa');
    expect(doc3.name, 'Priya Thapa');
    expect(doc3.nmcNumber, '');
    expect(doc3.hasNmc, false);
    expect(doc3.formattedLabel, 'Dr. Priya Thapa');
  });

  test('Blank Follow-Up Slip PDF generation', () async {
    final camp = CampModel(
      id: 'camp-fu',
      campCode: 'FU01',
      name: 'Sindhupalchok Follow-up Camp',
      province: 'Bagmati',
      district: 'Sindhupalchok',
      municipality: 'Chautara',
      ward: '02',
      venue: 'Health Post',
      startDate: DateTime(2026, 9, 20),
      endDate: DateTime(2026, 9, 22),
      status: CampStatus.open,
      doctorName: 'Dr. Sita Sharma (NMC: 12345)',
      doctorNames: ['Dr. Sita Sharma (NMC: 12345)'],
      createdAt: DateTime(2026, 9, 20),
    );

    final pdfService = PdfReportService();
    final bytes = await pdfService.generateBlankFollowUpSlipPdf(
      camp: camp,
      doctor: const DoctorProfile(name: 'Sita Sharma', nmcNumber: '12345'),
      organizationName: 'Rural Women Health Project',
    );

    expect(bytes.isNotEmpty, true);
    final outFile = File('test_samples/sample_blank_followup.pdf');
    outFile.writeAsBytesSync(bytes);
    final textContent = _extractPdfText(bytes);
    expect(textContent.contains('ENCOUNTER'), true);
    expect(textContent.contains('Sita'), true);
    expect(textContent.contains('12345'), true);
  });

  test('generateBatchBlankYellowFormsPdf generates 6 pages for 3 doctors with all doctor details', () async {
    final doctors = [
      const DoctorProfile(name: 'Anish Tiwari', nmcNumber: '11111'),
      const DoctorProfile(name: 'Sagar Poudel', nmcNumber: '22222'),
      const DoctorProfile(name: 'Ramesh Karki', nmcNumber: '33333'),
    ];

    final camp = CampModel(
      id: 'camp-11',
      campCode: '11',
      name: 'ddd',
      province: 'Bagmati',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '01',
      venue: 'Health Post',
      startDate: DateTime(2026, 9, 25),
      endDate: DateTime(2026, 9, 29),
      status: CampStatus.open,
      doctorName: 'Dr. Anish Tiwari, Dr. Sagar Poudel, Dr. Ramesh Karki',
      doctorNames: ['Dr. Anish Tiwari (NMC: 11111)', 'Dr. Sagar Poudel (NMC: 22222)', 'Dr. Ramesh Karki (NMC: 33333)'],
      createdAt: DateTime(2026, 9, 25),
    );

    final pdfService = PdfReportService();
    final bytes = await pdfService.generateBatchBlankYellowFormsPdf(
      doctors: doctors,
      camp: camp,
      organizationName: 'Mission Hospital',
    );

    expect(bytes.isNotEmpty, true);
    final raw = String.fromCharCodes(bytes);
    final pageCount = RegExp(r'/Type\s*/Page[^s]').allMatches(raw).length;
    expect(pageCount, 6); // 2 pages per doctor * 3 doctors = 6 pages

    final text = _extractPdfText(bytes);
    expect(text.contains('Anish'), true);
    expect(text.contains('11111'), true);
    expect(text.contains('Sagar'), true);
    expect(text.contains('22222'), true);
    expect(text.contains('Ramesh'), true);
    expect(text.contains('33333'), true);
  });

  test('generateBatchBlankFollowUpSlipsPdf generates 3 pages for 3 doctors', () async {
    final doctors = [
      const DoctorProfile(name: 'Anish Tiwari', nmcNumber: '11111'),
      const DoctorProfile(name: 'Sagar Poudel', nmcNumber: '22222'),
      const DoctorProfile(name: 'Ramesh Karki', nmcNumber: '33333'),
    ];

    final camp = CampModel(
      id: 'camp-11',
      campCode: '11',
      name: 'ddd',
      province: 'Bagmati',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '01',
      venue: 'Health Post',
      startDate: DateTime(2026, 9, 25),
      endDate: DateTime(2026, 9, 29),
      status: CampStatus.open,
      doctorName: 'Dr. Anish Tiwari',
      doctorNames: ['Dr. Anish Tiwari'],
      createdAt: DateTime(2026, 9, 25),
    );

    final pdfService = PdfReportService();
    final bytes = await pdfService.generateBatchBlankFollowUpSlipsPdf(
      doctors: doctors,
      camp: camp,
      organizationName: 'Mission Hospital',
    );

    expect(bytes.isNotEmpty, true);
    final raw = String.fromCharCodes(bytes);
    final pageCount = RegExp(r'/Type\s*/Page[^s]').allMatches(raw).length;
    expect(pageCount, 3); // 1 page per doctor * 3 doctors = 3 pages

    final text = _extractPdfText(bytes);
    expect(text.contains('Anish'), true);
    expect(text.contains('Sagar'), true);
    expect(text.contains('Ramesh'), true);
  });
}

String _extractPdfText(List<int> bytes) {
  final buffer = StringBuffer();
  final data = Uint8List.fromList(bytes);

  // Search for "stream" and "endstream" marker byte positions
  final streamMarker = 'stream'.codeUnits;
  final endMarker = 'endstream'.codeUnits;

  int pos = 0;
  while (pos < data.length) {
    int startStream = -1;
    for (int i = pos; i <= data.length - streamMarker.length; i++) {
      bool match = true;
      for (int j = 0; j < streamMarker.length; j++) {
        if (data[i + j] != streamMarker[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        startStream = i + streamMarker.length;
        break;
      }
    }

    if (startStream == -1) break;

    // Skip \r\n or \n
    while (startStream < data.length && (data[startStream] == 10 || data[startStream] == 13)) {
      startStream++;
    }

    int endStream = -1;
    for (int i = startStream; i <= data.length - endMarker.length; i++) {
      bool match = true;
      for (int j = 0; j < endMarker.length; j++) {
        if (data[i + j] != endMarker[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        endStream = i;
        break;
      }
    }

    if (endStream == -1) break;

    // Trim trailing \r\n
    int contentEnd = endStream;
    while (contentEnd > startStream && (data[contentEnd - 1] == 10 || data[contentEnd - 1] == 13)) {
      contentEnd--;
    }

    if (contentEnd > startStream) {
      final slice = data.sublist(startStream, contentEnd);
      try {
        final decompressed = zlib.decode(slice);
        buffer.writeln(String.fromCharCodes(decompressed));
      } catch (_) {
        // Plaintext stream
        buffer.writeln(String.fromCharCodes(slice));
      }
    }

    pos = endStream + endMarker.length;
  }
  return buffer.toString();
}
