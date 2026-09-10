import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'ocr_form_service.dart';

class DocumentCaptureService {
  final ImagePicker _picker;

  DocumentCaptureService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// Scans physical documents with automatic 4-corner edge detection,
  /// perspective rectification, shadow removal, and contrast enhancement.
  ///
  /// On Android, uses native Google Play Services Document Scanner.
  /// On Desktop, iOS, or Web, seamlessly falls back to camera or file picker.
  Future<List<XFile>> scanDocumentPages({int pageLimit = 2}) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final scanner = DocumentScanner(
          options: DocumentScannerOptions(
            documentFormats: {DocumentFormat.jpeg},
            mode: ScannerMode.full,
            pageLimit: pageLimit,
            isGalleryImport: true,
          ),
        );

        final result = await scanner.scanDocument();
        await scanner.close();

        final imagePaths = result.images;
        if (imagePaths != null && imagePaths.isNotEmpty) {
          return imagePaths.map((p) => XFile(p)).toList();
        }
        return [];
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[DocCapture] DocumentScanner failed or cancelled: $e. Falling back to camera/picker.');
        }
      }
    }

    // Fallback: standard camera capture
    final single = await captureFromCamera();
    return single != null ? [single] : [];
  }

  /// Scans a single document page with edge detection and perspective flattening.
  Future<XFile?> scanSingleDocumentPage() async {
    final list = await scanDocumentPages(pageLimit: 1);
    return list.isNotEmpty ? list.first : null;
  }

  /// Captures document photo from device camera at FULL RESOLUTION.
  ///
  /// For OCR accuracy, we do NOT compress the image. The full-resolution
  /// camera sensor output gives ML Kit the best chance of reading
  /// handwritten text on forms.
  Future<XFile?> captureFromCamera() async {
    return await _picker.pickImage(
      source: ImageSource.camera,
      // No imageQuality set = full resolution (100%).
      // JPEG compression destroys fine details needed for handwriting OCR.
      // No maxWidth/maxHeight set = full sensor resolution.
      preferredCameraDevice: CameraDevice.rear,
    );
  }

  /// Selects existing Yellow Form image from device gallery or filesystem.
  /// Full resolution preserved for OCR.
  Future<XFile?> pickFromGallery() async {
    return await _picker.pickImage(
      source: ImageSource.gallery,
      // No imageQuality compression for OCR accuracy
    );
  }

  /// Selects multiple images from device gallery (e.g. Page 1 Front + Page 2 Back)
  /// Full resolution preserved for OCR.
  Future<List<XFile>> pickMultipleImages() async {
    return await _picker.pickMultiImage(
      // No imageQuality compression for OCR accuracy
    );
  }

  /// Returns pre-configured high-fidelity Yellow Form text for demo & automated testing
  String getSampleFormText(String sampleType) {
    switch (sampleType.toLowerCase()) {
      case 'page1':
      case 'front':
        return OcrFormService.samplePage1Text;
      case 'page2':
      case 'back':
        return OcrFormService.samplePage2Text;
      case 'full':
      default:
        return OcrFormService.sampleFullFormText;
    }
  }
}
