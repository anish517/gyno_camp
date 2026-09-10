import 'package:image_picker/image_picker.dart';
import 'ocr_form_service.dart';

class DocumentCaptureService {
  final ImagePicker _picker;

  DocumentCaptureService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

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
