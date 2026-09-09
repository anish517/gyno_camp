import 'package:image_picker/image_picker.dart';
import 'ocr_form_service.dart';

class DocumentCaptureService {
  final ImagePicker _picker;

  DocumentCaptureService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// Captures document photo from device camera
  Future<XFile?> captureFromCamera() async {
    return await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      preferredCameraDevice: CameraDevice.rear,
    );
  }

  /// Selects existing Yellow Form image from device gallery or filesystem
  Future<XFile?> pickFromGallery() async {
    return await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
  }

  /// Selects multiple images from device gallery (e.g. Page 1 Front + Page 2 Back)
  Future<List<XFile>> pickMultipleImages() async {
    return await _picker.pickMultiImage(imageQuality: 90);
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
