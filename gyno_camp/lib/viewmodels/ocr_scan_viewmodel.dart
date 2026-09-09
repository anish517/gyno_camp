import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/document_capture_service.dart';
import '../models/ocr_scan_result_model.dart';
import '../models/patient_model.dart';
import '../repositories/ocr_repository.dart';

import '../core/services/duplicate_detection_service.dart';
import '../repositories/patient_repository.dart';

class OcrScanState {
  final bool isProcessing;
  final bool isSaving;
  final OcrScanResultModel? page1Scan;
  final OcrScanResultModel? page2Scan;
  final OcrScanResultModel? scanResult;
  final int activeInspectionPage; // 1 = Front Page, 2 = Back Page
  final String? errorMessage;
  final String? successMessage;
  final PatientModel? committedPatient;
  final DuplicateCheckResult duplicateResult;

  const OcrScanState({
    this.isProcessing = false,
    this.isSaving = false,
    this.page1Scan,
    this.page2Scan,
    this.scanResult,
    this.activeInspectionPage = 1,
    this.errorMessage,
    this.successMessage,
    this.committedPatient,
    this.duplicateResult = const DuplicateCheckResult.none(),
  });

  bool get hasPage1 => page1Scan != null;
  bool get hasPage2 => page2Scan != null;
  bool get isDualReady => hasPage1 && hasPage2;
  bool get hasScanResult => scanResult != null;
  bool get hasDuplicate => duplicateResult.hasDuplicate;

  OcrScanState copyWith({
    bool? isProcessing,
    bool? isSaving,
    OcrScanResultModel? page1Scan,
    OcrScanResultModel? page2Scan,
    OcrScanResultModel? scanResult,
    int? activeInspectionPage,
    String? errorMessage,
    String? successMessage,
    PatientModel? committedPatient,
    DuplicateCheckResult? duplicateResult,
    bool clearPage1 = false,
    bool clearPage2 = false,
    bool clearScanResult = false,
  }) {
    return OcrScanState(
      isProcessing: isProcessing ?? this.isProcessing,
      isSaving: isSaving ?? this.isSaving,
      page1Scan: clearPage1 ? null : (page1Scan ?? this.page1Scan),
      page2Scan: clearPage2 ? null : (page2Scan ?? this.page2Scan),
      scanResult: clearScanResult ? null : (scanResult ?? this.scanResult),
      activeInspectionPage: activeInspectionPage ?? this.activeInspectionPage,
      errorMessage: errorMessage,
      successMessage: successMessage,
      committedPatient: committedPatient ?? this.committedPatient,
      duplicateResult: duplicateResult ?? this.duplicateResult,
    );
  }
}

class OcrScanViewModel extends StateNotifier<OcrScanState> {
  final IOcrRepository _repository;
  final IPatientRepository _patientRepository;
  final DocumentCaptureService _captureService;

  OcrScanViewModel({
    IOcrRepository? repository,
    IPatientRepository? patientRepository,
    DocumentCaptureService? captureService,
  })  : _repository = repository ?? OcrRepository(),
        _patientRepository = patientRepository ?? PatientRepository(),
        _captureService = captureService ?? DocumentCaptureService(),
        super(const OcrScanState());

  /// Loads a high-fidelity sample Yellow Form (Front page, Back page, or Full form)
  Future<void> loadSample(String sampleType) async {
    state = state.copyWith(isProcessing: true, errorMessage: null, successMessage: null);
    try {
      if (sampleType == 'page1') {
        final text = _captureService.getSampleFormText('page1');
        final res = await _repository.processTextScan(text, pageNumber: 1, imagePath: 'test_samples/yellow_form_sample_page1.jpg');
        state = state.copyWith(
          isProcessing: false,
          page1Scan: res,
          scanResult: state.hasPage2 ? OcrScanResultModel.merge(res, state.page2Scan!) : res,
          successMessage: 'Page 1 (Demographics & Obstetric History) parsed.',
        );
      } else if (sampleType == 'page2') {
        final text = _captureService.getSampleFormText('page2');
        final res = await _repository.processTextScan(text, pageNumber: 2, imagePath: 'test_samples/yellow_form_sample_page2.jpg');
        state = state.copyWith(
          isProcessing: false,
          page2Scan: res,
          scanResult: state.hasPage1 ? OcrScanResultModel.merge(state.page1Scan!, res) : res,
          successMessage: 'Page 2 (POP Exam, Vitals & Treatment) parsed.',
        );
      } else {
        // Full 2-page combined
        final text1 = _captureService.getSampleFormText('page1');
        final text2 = _captureService.getSampleFormText('page2');
        final res1 = await _repository.processTextScan(text1, pageNumber: 1, imagePath: 'test_samples/yellow_form_sample_page1.jpg');
        final res2 = await _repository.processTextScan(text2, pageNumber: 2, imagePath: 'test_samples/yellow_form_sample_page2.jpg');
        final merged = OcrScanResultModel.merge(res1, res2);
        state = state.copyWith(
          isProcessing: false,
          page1Scan: res1,
          page2Scan: res2,
          scanResult: merged,
          successMessage: 'Complete 2-Page Yellow Form successfully digitized & merged.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to process Yellow Form sample: ${e.toString()}',
      );
    }
  }

  /// Captures specific page (1 or 2) using device camera
  Future<void> capturePage(int pageNumber) async {
    // Don't show loading spinner until the user has actually taken a photo
    state = state.copyWith(errorMessage: null);
    try {
      final photo = await _captureService.captureFromCamera();
      if (photo == null) {
        return; // user cancelled — nothing to do
      }
      // Photo confirmed — now show the processing indicator
      state = state.copyWith(isProcessing: true);
      final result = await _repository.processImageScan(photo, pageNumber: pageNumber);
      if (pageNumber == 1) {
        final merged = state.hasPage2 ? OcrScanResultModel.merge(result, state.page2Scan!) : null;
        state = state.copyWith(
          isProcessing: false,
          page1Scan: result,
          scanResult: merged ?? (state.hasPage2 ? null : result),
          successMessage: 'Page 1 (Front) captured successfully.',
        );
      } else {
        final merged = state.hasPage1 ? OcrScanResultModel.merge(state.page1Scan!, result) : null;
        state = state.copyWith(
          isProcessing: false,
          page2Scan: result,
          scanResult: merged ?? (state.hasPage1 ? null : result),
          successMessage: 'Page 2 (Back) captured successfully.',
        );
      }
    } catch (e) {
      final msg = e.toString();
      final friendlyMsg = msg.contains('camera_access_denied') || msg.contains('permission')
          ? 'Camera permission was denied. Please grant camera permission or use "Upload File".'
          : 'Camera capture error: $msg';
      state = state.copyWith(
        isProcessing: false,
        errorMessage: friendlyMsg,
      );
    }
  }

  /// Legacy single camera capture
  Future<void> captureWithCamera() => capturePage(1);

  /// Picks image for specific page slot (1 or 2)
  Future<void> pickPage(int pageNumber) async {
    // Don't show loading spinner until the user has actually chosen a file
    state = state.copyWith(errorMessage: null);
    try {
      final photo = await _captureService.pickFromGallery();
      if (photo == null) {
        return; // user cancelled — nothing to do
      }
      // File confirmed — now show the processing indicator
      state = state.copyWith(isProcessing: true);
      final result = await _repository.processImageScan(photo, pageNumber: pageNumber);
      if (pageNumber == 1) {
        final merged = state.hasPage2 ? OcrScanResultModel.merge(result, state.page2Scan!) : null;
        state = state.copyWith(
          isProcessing: false,
          page1Scan: result,
          scanResult: merged ?? (state.hasPage2 ? null : result),
          successMessage: 'Page 1 (Front) imported successfully.',
        );
      } else {
        final merged = state.hasPage1 ? OcrScanResultModel.merge(state.page1Scan!, result) : null;
        state = state.copyWith(
          isProcessing: false,
          page2Scan: result,
          scanResult: merged ?? (state.hasPage1 ? null : result),
          successMessage: 'Page 2 (Back) imported successfully.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Image pick error: ${e.toString()}',
      );
    }
  }

  /// Legacy single gallery picker
  Future<void> pickFromGallery() => pickPage(1);

  /// Selects both Page 1 and Page 2 at once via multi-image picker
  Future<void> pickBothPages() async {
    // Don't show loading spinner until the user has actually chosen files
    state = state.copyWith(errorMessage: null);
    try {
      final photos = await _captureService.pickMultipleImages();
      if (photos.isEmpty) {
        return; // user cancelled — nothing to do
      }
      // Files confirmed — now show the processing indicator
      state = state.copyWith(isProcessing: true);
      if (photos.length == 1) {
        final res = await _repository.processImageScan(photos[0], pageNumber: 1);
        state = state.copyWith(
          isProcessing: false,
          page1Scan: res,
          scanResult: res,
          successMessage: '1 document page imported.',
        );
        return;
      }

      // Process first as Page 1, second as Page 2
      final res1 = await _repository.processImageScan(photos[0], pageNumber: 1);
      final res2 = await _repository.processImageScan(photos[1], pageNumber: 2);
      final merged = OcrScanResultModel.merge(res1, res2);

      state = state.copyWith(
        isProcessing: false,
        page1Scan: res1,
        page2Scan: res2,
        scanResult: merged,
        successMessage: 'Both Page 1 (Front) & Page 2 (Back) successfully imported & merged!',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Multi-image pick error: ${e.toString()}',
      );
    }
  }

  /// Combines Page 1 and Page 2 and proceeds to verification
  void mergeAndProceed() {
    if (state.hasPage1 && state.hasPage2) {
      final merged = OcrScanResultModel.merge(state.page1Scan!, state.page2Scan!);
      state = state.copyWith(scanResult: merged);
    } else if (state.hasPage1) {
      state = state.copyWith(scanResult: state.page1Scan);
    } else if (state.hasPage2) {
      state = state.copyWith(scanResult: state.page2Scan);
    }
  }

  /// Switches active inspection tab between Page 1 and Page 2
  void switchInspectionPage(int page) {
    state = state.copyWith(activeInspectionPage: page);
  }

  /// Clears a specific page slot
  void clearSlot(int pageNumber) {
    if (pageNumber == 1) {
      state = state.copyWith(clearPage1: true, clearScanResult: !state.hasPage2);
    } else {
      state = state.copyWith(clearPage2: true, clearScanResult: !state.hasPage1);
    }
  }

  /// Updates a demographic field during human verification
  void updateDemographic(String key, dynamic value, {String? campId}) {
    if (state.scanResult == null) return;
    final updatedDemo = Map<String, dynamic>.from(state.scanResult!.demographics);
    updatedDemo[key] = value;
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(demographics: updatedDemo),
    );
    if (campId != null && campId.isNotEmpty) {
      runLiveDuplicateCheck(campId);
    }
  }

  /// Runs duplicate detection against SQLite camp registry
  Future<void> runLiveDuplicateCheck(String campId) async {
    if (state.scanResult == null) {
      state = state.copyWith(duplicateResult: const DuplicateCheckResult.none());
      return;
    }
    final demo = state.scanResult!.demographics;
    final firstName = demo['firstName'] as String? ?? '';
    final surname = demo['surname'] as String? ?? '';
    final age = demo['age'] as int? ?? 0;
    final mobile = demo['mobile'] as String? ?? '';
    final ward = demo['ward'] as String? ?? '';
    final spouseOrFather = demo['relativeName'] as String?;
    final maritalStatus = demo['maritalStatus'] as String?;

    if (firstName.trim().isEmpty && mobile.trim().isEmpty) {
      state = state.copyWith(duplicateResult: const DuplicateCheckResult.none());
      return;
    }

    final result = await _patientRepository.checkDuplicate(
      campId: campId,
      firstName: firstName,
      surname: surname,
      age: age,
      mobile: mobile,
      ward: ward,
      spouseOrFatherName: spouseOrFather,
      maritalStatus: maritalStatus,
    );

    state = state.copyWith(duplicateResult: result);
  }

  /// Updates a vital sign field during human verification
  void updateVital(String key, dynamic value) {
    if (state.scanResult == null) return;
    final updatedVitals = Map<String, dynamic>.from(state.scanResult!.vitals);
    updatedVitals[key] = value;
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(vitals: updatedVitals),
    );
  }

  /// Updates POP staging
  void updatePopStage(String key, dynamic value) {
    if (state.scanResult == null) return;
    final updatedPop = Map<String, dynamic>.from(state.scanResult!.popStaging);
    updatedPop[key] = value;

    // Recalculate highest
    final ant = updatedPop['anteriorStage'] as int? ?? 0;
    final mid = updatedPop['middleStage'] as int? ?? 0;
    final post = updatedPop['posteriorStage'] as int? ?? 0;
    updatedPop['highestPopStage'] = [ant, mid, post].reduce((a, b) => a > b ? a : b);

    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(popStaging: updatedPop),
    );
  }

  /// Toggles diagnosis on/off
  void toggleDiagnosis(String diagnosis) {
    if (state.scanResult == null) return;
    final list = List<String>.from(state.scanResult!.diagnoses);
    if (list.contains(diagnosis)) {
      list.remove(diagnosis);
    } else {
      list.add(diagnosis);
    }
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(diagnoses: list),
    );
  }

  /// Toggles medication on/off
  void toggleMedication(String medication) {
    if (state.scanResult == null) return;
    final list = List<String>.from(state.scanResult!.medications);
    if (list.contains(medication)) {
      list.remove(medication);
    } else {
      list.add(medication);
    }
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(medications: list),
    );
  }

  /// Commits verified scanned patient and clinical record to SQLite
  Future<PatientModel?> confirmAndCommit({
    required String campId,
    required String campCode,
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    if (state.scanResult == null) return null;

    state = state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    try {
      final savedPatient = await _repository.commitVerifiedScan(
        verifiedScan: state.scanResult!,
        campId: campId,
        campCode: campCode,
        userId: userId,
        userName: userName,
        deviceId: deviceId,
      );

      state = state.copyWith(
        isSaving: false,
        committedPatient: savedPatient,
        successMessage: 'Patient ${savedPatient.patientId} verified & saved directly to local database!',
      );
      return savedPatient;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save scanned record: ${e.toString()}',
      );
      return null;
    }
  }

  /// Clears state to start a new scan
  void resetScan() {
    state = const OcrScanState();
  }
}

final ocrScanProvider = StateNotifierProvider<OcrScanViewModel, OcrScanState>((ref) {
  return OcrScanViewModel();
});
