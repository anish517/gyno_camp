import 'package:image_picker/image_picker.dart';
import 'ocr_form_service.dart';

class DocumentCaptureService {
  final ImagePicker _picker;

  DocumentCaptureService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// Captures document photo from device camera
  Future<XFile?> captureFromCamera() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      return photo;
    } catch (e) {
      return null;
    }
  }

  /// Selects existing Yellow Form image from device gallery or filesystem
  Future<XFile?> pickFromGallery() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      return image;
    } catch (e) {
      return null;
    }
  }

  /// Selects multiple images from device gallery (e.g. Page 1 Front + Page 2 Back)
  Future<List<XFile>> pickMultipleImages() async {
    try {
      final images = await _picker.pickMultiImage(imageQuality: 90);
      return images;
    } catch (e) {
      return [];
    }
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
