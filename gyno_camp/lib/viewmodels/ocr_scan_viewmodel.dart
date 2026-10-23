import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/document_capture_service.dart';
import '../core/services/session_service.dart';
import '../models/ocr_scan_result_model.dart';
import '../models/patient_model.dart';
import '../repositories/ocr_repository.dart';

import '../core/services/duplicate_detection_service.dart';
import '../repositories/patient_repository.dart';

/// Safely extracts complaintDetails as `Map<String, dynamic>` regardless of
/// whether it's a List (from Gemini) or already a Map.
Map<String, dynamic> _safeComplaintDetailsMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is List) {
    final result = <String, dynamic>{};
    for (final item in raw) {
      if (item is Map) {
        final key = item['complaint']?.toString().trim();
        if (key != null && key.isNotEmpty) {
          result[key] = <String, dynamic>{
            'duration': item['duration']?.toString() ?? '',
            'remarks': item['remarks']?.toString() ?? '',
            'subOption': item['subOptions'] is List
                ? (item['subOptions'] as List).join(', ')
                : (item['subOption']?.toString() ?? ''),
          };
        }
      }
    }
    return result;
  }
  return <String, dynamic>{};
}

class OcrScanState {
  final bool isProcessing;
  final bool isSaving;
  final OcrScanResultModel? page1Scan;
  final OcrScanResultModel? page2Scan;
  final OcrScanResultModel? scanResult;
  final int activeInspectionPage; // 1 = Front Page, 2 = Back Page
  final OcrEngineMode engineMode; // auto, onlineGemini, offlineOnly
  final String? errorMessage;
  final String? successMessage;
  final PatientModel? committedPatient;
  final DuplicateCheckResult duplicateResult;
  final bool isPatientIdConflict;
  final String? patientIdConflictReason;

  const OcrScanState({
    this.isProcessing = false,
    this.isSaving = false,
    this.page1Scan,
    this.page2Scan,
    this.scanResult,
    this.activeInspectionPage = 1,
    this.engineMode = OcrEngineMode.auto,
    this.errorMessage,
    this.successMessage,
    this.committedPatient,
    this.duplicateResult = const DuplicateCheckResult.none(),
    this.isPatientIdConflict = false,
    this.patientIdConflictReason,
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
    OcrEngineMode? engineMode,
    String? errorMessage,
    String? successMessage,
    PatientModel? committedPatient,
    DuplicateCheckResult? duplicateResult,
    bool? isPatientIdConflict,
    String? patientIdConflictReason,
    bool clearPatientIdConflict = false,
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
      engineMode: engineMode ?? this.engineMode,
      errorMessage: errorMessage,
      successMessage: successMessage,
      committedPatient: committedPatient ?? this.committedPatient,
      duplicateResult: duplicateResult ?? this.duplicateResult,
      isPatientIdConflict: clearPatientIdConflict ? false : (isPatientIdConflict ?? this.isPatientIdConflict),
      patientIdConflictReason: clearPatientIdConflict ? null : (patientIdConflictReason ?? this.patientIdConflictReason),
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
        super(OcrScanState(engineMode: _loadInitialEngineMode()));

  static OcrEngineMode _loadInitialEngineMode() {
    final saved = SessionService.current?.getOcrEngineMode();
    if (saved == 'onlineGemini') return OcrEngineMode.onlineGemini;
    if (saved == 'offlineOnly') return OcrEngineMode.offlineOnly;
    return OcrEngineMode.auto;
  }

  Future<void> setEngineMode(OcrEngineMode mode) async {
    state = state.copyWith(engineMode: mode);
    await SessionService.current?.saveOcrEngineMode(mode.name);
  }

  /// Loads a high-fidelity sample Yellow Form (Front page, Back page, or Full form)
  Future<void> loadSample(String sampleType) async {
    state = state.copyWith(isProcessing: true, errorMessage: null, successMessage: null);
    try {
      if (sampleType == 'page1') {
        final text = _captureService.getSampleFormText('page1');
        final res = await _repository.processTextScan(text, pageNumber: 1, imagePath: 'test_samples/yellow_form_sample_page1.jpg');
        if (!mounted) return;
        state = state.copyWith(
          isProcessing: false,
          page1Scan: res,
          scanResult: state.hasPage2 ? OcrScanResultModel.merge(res, state.page2Scan!) : null,
          successMessage: 'Page 1 (Demographics & Obstetric History) parsed.',
        );
      } else if (sampleType == 'page2') {
        final text = _captureService.getSampleFormText('page2');
        final res = await _repository.processTextScan(text, pageNumber: 2, imagePath: 'test_samples/yellow_form_sample_page2.jpg');
        if (!mounted) return;
        state = state.copyWith(
          isProcessing: false,
          page2Scan: res,
          scanResult: state.hasPage1 ? OcrScanResultModel.merge(state.page1Scan!, res) : null,
          successMessage: 'Page 2 (POP Exam, Vitals & Treatment) parsed.',
        );
      } else {
        // Full 2-page combined
        final text1 = _captureService.getSampleFormText('page1');
        final text2 = _captureService.getSampleFormText('page2');
        final res1 = await _repository.processTextScan(text1, pageNumber: 1, imagePath: 'test_samples/yellow_form_sample_page1.jpg');
        final res2 = await _repository.processTextScan(text2, pageNumber: 2, imagePath: 'test_samples/yellow_form_sample_page2.jpg');
        if (!mounted) return;
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
      if (!mounted) return;
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to process Yellow Form sample: ${e.toString()}',
      );
    }
  }

  /// Captures specific page (1 or 2) using edge-detecting document scanner or camera
  Future<void> capturePage(int pageNumber) async {
    // Don't show loading spinner until the user has actually taken a photo
    state = state.copyWith(errorMessage: null);
    try {
      final photo = await _captureService.scanSingleDocumentPage();
      if (photo == null) {
        return; // user cancelled — nothing to do
      }
      if (!mounted) return;
      // Photo confirmed — now show the processing indicator
      state = state.copyWith(isProcessing: true);
      final result = await _repository.processImageScan(photo, pageNumber: pageNumber, engineMode: state.engineMode);
      if (!mounted) return;
      if (pageNumber == 1) {
        state = state.copyWith(
          isProcessing: false,
          page1Scan: result,
          // Stay on dual-slot view so user can review Slot 1 status and proceed to Slot 2
          successMessage: 'Page 1 (Front) captured successfully. Capture Page 2 or tap Review.',
        );
      } else {
        state = state.copyWith(
          isProcessing: false,
          page2Scan: result,
          // Stay on dual-slot view so user can see both slots ready
          successMessage: 'Page 2 (Back) captured successfully. Both pages ready for review.',
        );
      }
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
      // File confirmed — now show the processing indicator
      state = state.copyWith(isProcessing: true);
      final result = await _repository.processImageScan(photo, pageNumber: pageNumber, engineMode: state.engineMode);
      if (!mounted) return;
      if (pageNumber == 1) {
        state = state.copyWith(
          isProcessing: false,
          page1Scan: result,
          // Stay on dual-slot view so user can review Slot 1 status and proceed to Slot 2
          successMessage: 'Page 1 (Front) imported successfully. Import Page 2 or tap Review.',
        );
      } else {
        state = state.copyWith(
          isProcessing: false,
          page2Scan: result,
          // Stay on dual-slot view so user can see both slots ready
          successMessage: 'Page 2 (Back) imported successfully. Both pages ready for review.',
        );
      }
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
      // Files confirmed — now show the processing indicator
      state = state.copyWith(isProcessing: true);
      if (photos.length == 1) {
        final res = await _repository.processImageScan(photos[0], pageNumber: 1, engineMode: state.engineMode);
        if (!mounted) return;
        state = state.copyWith(
          isProcessing: false,
          page1Scan: res,
          successMessage: '1 document page imported. Import Page 2 or tap Review.',
        );
        return;
      }

      // Process first as Page 1, second as Page 2
      final res1 = await _repository.processImageScan(photos[0], pageNumber: 1, engineMode: state.engineMode);
      final res2 = await _repository.processImageScan(photos[1], pageNumber: 2, engineMode: state.engineMode);
      if (!mounted) return;
      final merged = OcrScanResultModel.merge(res1, res2);

      state = state.copyWith(
        isProcessing: false,
        page1Scan: res1,
        page2Scan: res2,
        scanResult: merged,
        successMessage: 'Both Page 1 (Front) & Page 2 (Back) successfully imported & merged!',
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Multi-image pick error: ${e.toString()}',
      );
    }
  }

  /// Scans both Page 1 and Page 2 in a unified edge-detecting document scanner session
  Future<void> scanBothPagesWithDocumentScanner() async {
    state = state.copyWith(errorMessage: null);
    try {
      final photos = await _captureService.scanDocumentPages(pageLimit: 2);
      if (photos.isEmpty) return;
      if (!mounted) return;

      state = state.copyWith(isProcessing: true);
      if (photos.length == 1) {
        final res = await _repository.processImageScan(photos[0], pageNumber: 1, engineMode: state.engineMode);
        if (!mounted) return;
        state = state.copyWith(
          isProcessing: false,
          page1Scan: res,
          successMessage: 'Page 1 scanned and rectified. Capture Page 2 or tap Review.',
        );
        return;
      }

      final res1 = await _repository.processImageScan(photos[0], pageNumber: 1, engineMode: state.engineMode);
      final res2 = await _repository.processImageScan(photos[1], pageNumber: 2, engineMode: state.engineMode);
      if (!mounted) return;
      final merged = OcrScanResultModel.merge(res1, res2);

      state = state.copyWith(
        isProcessing: false,
        page1Scan: res1,
        page2Scan: res2,
        scanResult: merged,
        successMessage: 'Both Page 1 (Front) & Page 2 (Back) scanned, deskewed & merged!',
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Document scanner error: ${e.toString()}',
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

  /// Returns from verification pane to the dual-slot capture screen without losing captured scans
  void returnToCaptureSlots() {
    state = state.copyWith(clearScanResult: true);
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
  void updateDemographic(String key, dynamic value, {String? campId, String? campCode}) {
    if (state.scanResult == null) return;
    final updatedDemo = Map<String, dynamic>.from(state.scanResult!.demographics);
    updatedDemo[key] = value;
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(demographics: updatedDemo),
    );
    if (key == 'patientId') {
      checkPatientIdAvailability(value?.toString() ?? '', campCode: campCode);
    }
    if (campId != null && campId.isNotEmpty) {
      runLiveDuplicateCheck(campId);
    }
  }

  /// Checks whether a scanned or manually entered patient token ID is already taken
  Future<void> checkPatientIdAvailability(String candidateId, {String? campCode}) async {
    final clean = candidateId.trim();
    if (clean.isEmpty) {
      state = state.copyWith(clearPatientIdConflict: true);
      return;
    }
    final normalized = PatientModel.normalizePatientId(
      rawInput: clean,
      campCode: campCode ?? '',
    );
    final target = normalized.isNotEmpty ? normalized : clean;
    final isTaken = await _patientRepository.isPatientIdTaken(target);
    if (!mounted) return;
    if (isTaken) {
      state = state.copyWith(
        isPatientIdConflict: true,
        patientIdConflictReason: 'Token ID "$target" is already registered in the local database.',
      );
    } else {
      state = state.copyWith(clearPatientIdConflict: true);
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

    if (!mounted) return;
    state = state.copyWith(duplicateResult: result);
  }

  /// Updates an obstetric / anamnesis field during human verification
  void updateObstetric(String key, dynamic value) {
    if (state.scanResult == null) return;
    final updatedObs = Map<String, dynamic>.from(state.scanResult!.obstetrics);
    updatedObs[key] = value;
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(obstetrics: updatedObs),
    );
  }

  /// Toggles clinical complaint in obstetrics
  void toggleClinicalComplaint(String complaint) {
    if (state.scanResult == null) return;
    final updatedObs = Map<String, dynamic>.from(state.scanResult!.obstetrics);
    final rawList = updatedObs['clinicalComplaints'];
    final List<String> complaints = rawList is List ? List<String>.from(rawList) : [];

    final clean = complaint.toLowerCase().trim();
    final existingIndex = complaints.indexWhere((c) {
      final cLow = c.toLowerCase().trim();
      if (cLow == clean) return true;
      if (clean == 'prolapse' && (cLow.contains('prolapse') || cLow.contains('hanging') || cLow.contains('पाठेघर'))) return true;
      if (clean == 'discharge' && (cLow.contains('discharge') || cLow.contains('itching') || cLow.contains('स्राव'))) return true;
      if (clean == 'urine' && (cLow.contains('urine') || cLow.contains('पिसाब'))) return true;
      if (clean == 'stool' && (cLow.contains('stool') || cLow.contains('दिसा'))) return true;
      if (clean == 'menstrual' && (cLow.contains('menstrual') || cLow.contains('महिनावारी'))) return true;
      if (clean == 'infertility' && (cLow.contains('infertility') || cLow.contains('बाँझोपन'))) return true;
      if (clean == 'lower_abdomen_pain' && (cLow == 'lower_abdomen_pain' || (cLow.contains('pain') && !cLow.contains('back')))) return true;
      if (clean == 'lower_back_pain' && (cLow == 'lower_back_pain' || cLow.contains('back') || cLow.contains('ढाड'))) return true;
      if (clean == 'checkup' && (cLow.contains('checkup') || cLow.contains('जाँच'))) return true;
      return false;
    });

    if (existingIndex != -1) {
      complaints.removeAt(existingIndex);
    } else {
      complaints.add(complaint);
    }
    updatedObs['clinicalComplaints'] = complaints;
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(obstetrics: updatedObs),
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

    if (key == 'highestPopStage' || key == 'highestStage' || key == 'stage') {
      updatedPop['highestPopStage'] = value;
      updatedPop['highestStage'] = value;
      updatedPop['stage'] = value;
    } else {
      // Recalculate highest if anterior, middle, or posterior wall changed
      final ant = updatedPop['anteriorStage'] as int?;
      final mid = updatedPop['middleStage'] as int?;
      final post = updatedPop['posteriorStage'] as int?;
      if (ant != null || mid != null || post != null) {
        final calc = [ant ?? 0, mid ?? 0, post ?? 0].reduce((a, b) => a > b ? a : b);
        updatedPop['highestPopStage'] = calc;
        updatedPop['highestStage'] = calc;
        updatedPop['stage'] = calc;
      }
    }

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

  /// Explicitly adds a diagnosis if not already present
  void addDiagnosis(String diagnosis) {
    if (state.scanResult == null) return;
    final trimmed = diagnosis.trim();
    if (trimmed.isEmpty) return;
    final list = List<String>.from(state.scanResult!.diagnoses);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      state = state.copyWith(
        scanResult: state.scanResult!.copyWith(diagnoses: list),
      );
    }
  }

  /// Explicitly removes a diagnosis
  void removeDiagnosis(String diagnosis) {
    if (state.scanResult == null) return;
    final list = List<String>.from(state.scanResult!.diagnoses);
    if (list.remove(diagnosis)) {
      state = state.copyWith(
        scanResult: state.scanResult!.copyWith(diagnoses: list),
      );
    }
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

  /// Explicitly adds a medication if not already present
  void addMedication(String medication) {
    if (state.scanResult == null) return;
    final trimmed = medication.trim();
    if (trimmed.isEmpty) return;
    final list = List<String>.from(state.scanResult!.medications);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      state = state.copyWith(
        scanResult: state.scanResult!.copyWith(medications: list),
      );
    }
  }

  /// Explicitly removes a medication
  void removeMedication(String medication) {
    if (state.scanResult == null) return;
    final list = List<String>.from(state.scanResult!.medications);
    if (list.remove(medication)) {
      state = state.copyWith(
        scanResult: state.scanResult!.copyWith(medications: list),
      );
    }
  }

  /// Updates surgical referral hospital destination
  void updateSurgicalReferral(String? referral) {
    if (state.scanResult == null) return;
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(
        surgicalReferral: referral,
        clearSurgicalReferral: referral == null,
      ),
    );
  }

  /// Updates follow-up destination
  void updateFollowUpDestination(String? destination) {
    if (state.scanResult == null) return;
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(
        followUpDestination: destination,
        clearFollowUpDestination: destination == null,
      ),
    );
  }

  /// Updates surgery done and surgery route during human verification
  void updateSurgery({required bool done, String? type}) {
    if (state.scanResult == null) return;
    final updatedPop = Map<String, dynamic>.from(state.scanResult!.popStaging);
    updatedPop['surgeryDone'] = done;
    updatedPop['surgeryType'] = done ? type : null;

    final updatedScan = state.scanResult!.copyWith(
      surgeryDone: done,
      surgeryType: done ? type : null,
      clearSurgeryType: !done,
      popStaging: updatedPop,
    );

    final updatedPage2 = state.page2Scan?.copyWith(
      surgeryDone: done,
      surgeryType: done ? type : null,
      clearSurgeryType: !done,
      popStaging: updatedPop,
    );

    state = state.copyWith(
      scanResult: updatedScan,
      page2Scan: updatedPage2,
    );
  }

  /// Updates per-complaint duration or details in obstetrics
  void updateComplaintDetail(String complaint, {String? duration, String? remarks, dynamic subOption}) {
    if (state.scanResult == null) return;
    final updatedObs = Map<String, dynamic>.from(state.scanResult!.obstetrics);
    final details = _safeComplaintDetailsMap(updatedObs['complaintDetails']);
    final item = Map<String, dynamic>.from(details[complaint] as Map? ?? {});
    if (duration != null) item['duration'] = duration;
    if (remarks != null) item['remarks'] = remarks;
    if (subOption != null) item['subOption'] = subOption;
    details[complaint] = item;
    updatedObs['complaintDetails'] = details;

    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(obstetrics: updatedObs),
    );
  }

  /// Toggles specialized counseling topics (weak pelvic floor, POP, stress incontinence, urge incontinence, abdominal pain)
  void toggleCounseling(String topic) {
    if (state.scanResult == null) return;
    final current = List<String>.from(state.scanResult!.counseling);
    final exists = current.any((c) => c.toLowerCase() == topic.toLowerCase());
    if (exists) {
      current.removeWhere((c) => c.toLowerCase() == topic.toLowerCase());
    } else {
      current.add(topic);
    }

    final updatedScan = state.scanResult!.copyWith(counseling: current);
    final updatedPage2 = state.page2Scan?.copyWith(counseling: current);

    state = state.copyWith(
      scanResult: updatedScan,
      page2Scan: updatedPage2,
    );
  }

  /// Updates pessary insertion status, pessary type (ring, ring with support, ring with knob), and size (mm)
  void updatePessary({required bool ringPessary, String? pessaryType, int? size}) {
    if (state.scanResult == null) return;
    final updatedPop = Map<String, dynamic>.from(state.scanResult!.popStaging);
    updatedPop['ringPessary'] = ringPessary;
    updatedPop['pessaryType'] = ringPessary ? pessaryType : null;
    updatedPop['ringPessarySize'] = ringPessary ? size : null;

    final updatedScan = state.scanResult!.copyWith(
      ringPessary: ringPessary,
      pessaryType: ringPessary ? pessaryType : null,
      clearPessaryType: !ringPessary,
      ringPessarySize: ringPessary ? size : null,
      clearRingPessarySize: !ringPessary,
      popStaging: updatedPop,
    );

    final updatedPage2 = state.page2Scan?.copyWith(
      ringPessary: ringPessary,
      pessaryType: ringPessary ? pessaryType : null,
      clearPessaryType: !ringPessary,
      ringPessarySize: ringPessary ? size : null,
      clearRingPessarySize: !ringPessary,
      popStaging: updatedPop,
    );

    state = state.copyWith(
      scanResult: updatedScan,
      page2Scan: updatedPage2,
    );
  }

  /// Updates ring pessary status and size during human verification
  void updateRingPessary({required bool ringPessary, int? size}) {
    updatePessary(ringPessary: ringPessary, pessaryType: ringPessary ? 'ring' : null, size: size);
  }

  /// Sets examining doctor on scan result during human verification
  void setExaminingDoctor(String? doctor) {
    if (state.scanResult == null) return;
    final clean = doctor?.trim();
    final updated = state.scanResult!.copyWith(
      examiningDoctor: clean,
      clearExaminingDoctor: clean == null || clean.isEmpty,
      attendingDoctors: clean != null && clean.isNotEmpty ? [clean] : const [],
    );
    state = state.copyWith(scanResult: updated);
  }

  /// Toggles attending doctor in multi-doctor list during verification
  void toggleAttendingDoctor(String doctor) {
    if (state.scanResult == null) return;
    final clean = doctor.trim();
    if (clean.isEmpty) return;
    final list = List<String>.from(state.scanResult!.attendingDoctors);
    if (list.contains(clean)) {
      list.remove(clean);
    } else {
      list.add(clean);
    }
    final primary = list.isNotEmpty ? list.first : null;
    final updated = state.scanResult!.copyWith(
      examiningDoctor: primary,
      clearExaminingDoctor: primary == null,
      attendingDoctors: list,
    );
    state = state.copyWith(scanResult: updated);
  }

  /// Sets examining nurse on scan result during human verification
  void setExaminingNurse(String? nurse) {
    if (state.scanResult == null) return;
    final clean = nurse?.trim();
    final updated = state.scanResult!.copyWith(
      examiningNurse: clean,
      clearExaminingNurse: clean == null || clean.isEmpty,
      attendingNurses: clean != null && clean.isNotEmpty ? [clean] : const [],
    );
    state = state.copyWith(scanResult: updated);
  }

  /// Toggles attending nurse in multi-nurse list during verification
  void toggleAttendingNurse(String nurse) {
    if (state.scanResult == null) return;
    final clean = nurse.trim();
    if (clean.isEmpty) return;
    final list = List<String>.from(state.scanResult!.attendingNurses);
    if (list.contains(clean)) {
      list.remove(clean);
    } else {
      list.add(clean);
    }
    final primary = list.isNotEmpty ? list.first : null;
    final updated = state.scanResult!.copyWith(
      examiningNurse: primary,
      clearExaminingNurse: primary == null,
      attendingNurses: list,
    );
    state = state.copyWith(scanResult: updated);
  }

  /// Sets level of treatment on scan result during human verification
  void setTreatmentLevel(String? level) {
    if (state.scanResult == null) return;
    final clean = (level == null || level.trim().isEmpty || level.trim() == 'none') ? null : level.trim();
    final updated = state.scanResult!.copyWith(
      treatmentLevel: clean,
      clearTreatmentLevel: clean == null,
    );
    state = state.copyWith(scanResult: updated);
  }

  /// Updates clinical notes (Station 6) on scan result
  void updateClinicalNotes(String? notes) {
    if (state.scanResult == null) return;
    final clean = (notes == null || notes.trim().isEmpty) ? null : notes.trim();
    final updated = state.scanResult!.copyWith(
      clinicalNotes: clean,
      clearClinicalNotes: clean == null,
    );
    state = state.copyWith(scanResult: updated);
  }

  /// Updates relative type ('Husband', 'Father', 'Mother', 'Guardian', 'Other')
  void updateRelativeType(String type) {
    if (state.scanResult == null) return;
    final updatedDemo = Map<String, dynamic>.from(state.scanResult!.demographics);
    updatedDemo['relativeType'] = type;
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(demographics: updatedDemo),
    );
  }

  /// Updates station dates on scan result
  void updateStationDate(String field, String? dateStr) {
    if (state.scanResult == null) return;
    final clean = (dateStr == null || dateStr.trim().isEmpty) ? null : dateStr.trim();
    final updated = switch (field) {
      'intakeDate' => state.scanResult!.copyWith(
          intakeDate: clean,
          clearIntakeDate: clean == null,
          demographics: {
            ...state.scanResult!.demographics,
            'intakeDate': clean,
            'date': clean,
          },
        ),
      'examDate' => state.scanResult!.copyWith(examDate: clean, clearExamDate: clean == null),
      'treatmentDate' => state.scanResult!.copyWith(treatmentDate: clean, clearTreatmentDate: clean == null),
      'conclusionDate' => state.scanResult!.copyWith(conclusionDate: clean, clearConclusionDate: clean == null),
      'labTestDate' => state.scanResult!.copyWith(labTestDate: clean, clearLabTestDate: clean == null),
      'outtakeDate' => state.scanResult!.copyWith(outtakeDate: clean, clearOuttakeDate: clean == null),
      _ => state.scanResult!,
    };
    state = state.copyWith(scanResult: updated);
  }

  /// Commits verified scanned patient and clinical record to SQLite
  Future<PatientModel?> confirmAndCommit({
    required String campId,
    required String campCode,
    required String userId,
    required String userName,
    String userRole = 'NURSE',
    required String deviceId,
    String? primaryDoctorName,
    List<String> attendingDoctorNames = const [],
    String? primaryNurseName,
    List<String> attendingNurseNames = const [],
  }) async {
    if (state.scanResult == null) return null;

    state = state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    try {
      final effectiveDoctor = primaryDoctorName ?? state.scanResult!.examiningDoctor;
      final effectiveAttending = attendingDoctorNames.isNotEmpty
          ? attendingDoctorNames
          : (state.scanResult!.attendingDoctors.isNotEmpty
              ? state.scanResult!.attendingDoctors
              : (effectiveDoctor != null ? [effectiveDoctor] : const <String>[]));

      final effectiveNurse = primaryNurseName ?? state.scanResult!.examiningNurse;
      final effectiveAttendingNurses = attendingNurseNames.isNotEmpty
          ? attendingNurseNames
          : (state.scanResult!.attendingNurses.isNotEmpty
              ? state.scanResult!.attendingNurses
              : (effectiveNurse != null ? [effectiveNurse] : const <String>[]));

      final savedPatient = await _repository.commitVerifiedScan(
        verifiedScan: state.scanResult!,
        campId: campId,
        campCode: campCode,
        userId: userId,
        userName: userName,
        userRole: userRole,
        deviceId: deviceId,
        primaryDoctorName: effectiveDoctor,
        attendingDoctorNames: effectiveAttending,
        primaryNurseName: effectiveNurse,
        attendingNurseNames: effectiveAttendingNurses,
      );

      if (!mounted) return savedPatient;
      state = state.copyWith(
        isSaving: false,
        committedPatient: savedPatient,
        successMessage: 'Patient ${savedPatient.patientId} verified & saved directly to local database!',
      );
      return savedPatient;
    } catch (e) {
      if (!mounted) return null;
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
