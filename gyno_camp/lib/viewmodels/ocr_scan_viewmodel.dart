import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/document_capture_service.dart';
import '../models/ocr_scan_result_model.dart';
import '../models/patient_model.dart';
import '../repositories/ocr_repository.dart';

class OcrScanState {
  final bool isProcessing;
  final bool isSaving;
  final OcrScanResultModel? scanResult;
  final String? errorMessage;
  final String? successMessage;
  final PatientModel? committedPatient;

  const OcrScanState({
    this.isProcessing = false,
    this.isSaving = false,
    this.scanResult,
    this.errorMessage,
    this.successMessage,
    this.committedPatient,
  });

  bool get hasScanResult => scanResult != null;

  OcrScanState copyWith({
    bool? isProcessing,
    bool? isSaving,
    OcrScanResultModel? scanResult,
    String? errorMessage,
    String? successMessage,
    PatientModel? committedPatient,
  }) {
    return OcrScanState(
      isProcessing: isProcessing ?? this.isProcessing,
      isSaving: isSaving ?? this.isSaving,
      scanResult: scanResult ?? this.scanResult,
      errorMessage: errorMessage,
      successMessage: successMessage,
      committedPatient: committedPatient ?? this.committedPatient,
    );
  }
}

class OcrScanViewModel extends StateNotifier<OcrScanState> {
  final IOcrRepository _repository;
  final DocumentCaptureService _captureService;

  OcrScanViewModel({
    IOcrRepository? repository,
    DocumentCaptureService? captureService,
  })  : _repository = repository ?? OcrRepository(),
        _captureService = captureService ?? DocumentCaptureService(),
        super(const OcrScanState());

  /// Loads a high-fidelity sample Yellow Form (Front page, Back page, or Full form)
  Future<void> loadSample(String sampleType) async {
    state = state.copyWith(isProcessing: true, errorMessage: null, successMessage: null);
    try {
      final text = _captureService.getSampleFormText(sampleType);
      final result = await _repository.processTextScan(
        text,
        pageNumber: sampleType == 'page1' ? 1 : (sampleType == 'page2' ? 2 : 0),
        imagePath: 'assets/samples/yellow_form_$sampleType.png',
      );
      state = state.copyWith(
        isProcessing: false,
        scanResult: result,
        successMessage: 'Yellow Form successfully parsed (${(result.overallConfidence * 100).toInt()}% confidence).',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to process Yellow Form sample: ${e.toString()}',
      );
    }
  }

  /// Triggers device camera capture
  Future<void> captureWithCamera() async {
    state = state.copyWith(isProcessing: true, errorMessage: null);
    try {
      final photo = await _captureService.captureFromCamera();
      if (photo == null) {
        state = state.copyWith(isProcessing: false);
        return;
      }
      final result = await _repository.processImageScan(photo);
      state = state.copyWith(
        isProcessing: false,
        scanResult: result,
        successMessage: 'Document captured and parsed successfully.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Camera capture error: ${e.toString()}',
      );
    }
  }

  /// Selects existing photo from gallery / file system
  Future<void> pickFromGallery() async {
    state = state.copyWith(isProcessing: true, errorMessage: null);
    try {
      final photo = await _captureService.pickFromGallery();
      if (photo == null) {
        state = state.copyWith(isProcessing: false);
        return;
      }
      final result = await _repository.processImageScan(photo);
      state = state.copyWith(
        isProcessing: false,
        scanResult: result,
        successMessage: 'Form image imported and parsed successfully.',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Image pick error: ${e.toString()}',
      );
    }
  }

  /// Updates a demographic field during human verification
  void updateDemographic(String key, dynamic value) {
    if (state.scanResult == null) return;
    final updatedDemo = Map<String, dynamic>.from(state.scanResult!.demographics);
    updatedDemo[key] = value;
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(demographics: updatedDemo),
    );
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
