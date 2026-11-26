import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/document_capture_service.dart';
import '../core/services/gemini_ocr_service.dart';
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
  final String? processingStep;
  final bool isSaving;
  final OcrScanResultModel? page1Scan;
  final OcrScanResultModel? page2Scan;
  final OcrScanResultModel? scanResult;
  final Uint8List? page1ImageBytes;
  final String? page1ImagePath;
  final Uint8List? page2ImageBytes;
  final String? page2ImagePath;
  final List<OfflineScanQueueItem> offlineQueue;
  final bool isOfflineModeDetected;
  final int activeInspectionPage; // 1 = Front Page, 2 = Back Page
  final OcrEngineMode engineMode; // onlineGemini
  final String? errorMessage;
  final String? successMessage;
  final PatientModel? committedPatient;
  final DuplicateCheckResult duplicateResult;
  final bool isPatientIdConflict;
  final String? patientIdConflictReason;
  final String? activeArchiveItemId;
  final String? reviewingPatientUuid;
  final String? reviewingVisitId;

  const OcrScanState({
    this.isProcessing = false,
    this.processingStep,
    this.isSaving = false,
    this.page1Scan,
    this.page2Scan,
    this.scanResult,
    this.page1ImageBytes,
    this.page1ImagePath,
    this.page2ImageBytes,
    this.page2ImagePath,
    this.offlineQueue = const [],
    this.isOfflineModeDetected = false,
    this.activeInspectionPage = 1,
    this.engineMode = OcrEngineMode.onlineGemini,
    this.errorMessage,
    this.successMessage,
    this.committedPatient,
    this.duplicateResult = const DuplicateCheckResult.none(),
    this.isPatientIdConflict = false,
    this.patientIdConflictReason,
    this.activeArchiveItemId,
    this.reviewingPatientUuid,
    this.reviewingVisitId,
  });

  bool get hasPage1 => page1Scan != null;
  bool get hasPage2 => page2Scan != null;
  bool get hasPage1Image =>
      (page1ImageBytes != null && page1ImageBytes!.isNotEmpty) ||
      (page1ImagePath != null && page1ImagePath!.isNotEmpty) ||
      (page1Scan?.imagePath != null && page1Scan!.imagePath!.isNotEmpty);
  bool get hasPage2Image =>
      (page2ImageBytes != null && page2ImageBytes!.isNotEmpty) ||
      (page2ImagePath != null && page2ImagePath!.isNotEmpty) ||
      (page2Scan?.imagePath != null && page2Scan!.imagePath!.isNotEmpty);
  bool get hasAnyCapturedImage => hasPage1Image || hasPage2Image;
  bool get isDualReady => hasPage1 && hasPage2;
  bool get hasScanResult => scanResult != null;
  bool get hasDuplicate => duplicateResult.hasDuplicate;
  List<OfflineScanQueueItem> get pendingOfflineQueue =>
      offlineQueue.where((i) => i.isPendingOrFailed).toList();
  List<OfflineScanQueueItem> get completedScanArchive =>
      offlineQueue.where((i) => i.isCompleted && i.hasAnyImage).toList();
  bool get isReviewingCommittedScan =>
      (reviewingPatientUuid != null && reviewingPatientUuid!.isNotEmpty) ||
      (activeArchiveItemId != null &&
          offlineQueue.any(
            (i) => i.id == activeArchiveItemId && i.isCompleted,
          ));

  OcrScanState copyWith({
    bool? isProcessing,
    String? processingStep,
    bool clearProcessingStep = false,
    bool? isSaving,
    OcrScanResultModel? page1Scan,
    OcrScanResultModel? page2Scan,
    OcrScanResultModel? scanResult,
    Uint8List? page1ImageBytes,
    String? page1ImagePath,
    Uint8List? page2ImageBytes,
    String? page2ImagePath,
    List<OfflineScanQueueItem>? offlineQueue,
    bool? isOfflineModeDetected,
    int? activeInspectionPage,
    OcrEngineMode? engineMode,
    String? errorMessage,
    String? successMessage,
    PatientModel? committedPatient,
    DuplicateCheckResult? duplicateResult,
    bool? isPatientIdConflict,
    String? patientIdConflictReason,
    String? activeArchiveItemId,
    bool clearActiveArchiveItem = false,
    String? reviewingPatientUuid,
    String? reviewingVisitId,
    bool clearReviewContext = false,
    bool clearPatientIdConflict = false,
    bool clearPage1 = false,
    bool clearPage2 = false,
    bool clearPage1Image = false,
    bool clearPage2Image = false,
    bool clearScanResult = false,
  }) {
    return OcrScanState(
      isProcessing: isProcessing ?? this.isProcessing,
      processingStep: clearProcessingStep ? null : (processingStep ?? ((isProcessing == false) ? null : this.processingStep)),
      isSaving: isSaving ?? this.isSaving,
      page1Scan: clearPage1 ? null : (page1Scan ?? this.page1Scan),
      page2Scan: clearPage2 ? null : (page2Scan ?? this.page2Scan),
      scanResult: clearScanResult ? null : (scanResult ?? this.scanResult),
      page1ImageBytes: (clearPage1 || clearPage1Image) ? null : (page1ImageBytes ?? this.page1ImageBytes),
      page1ImagePath: (clearPage1 || clearPage1Image) ? null : (page1ImagePath ?? this.page1ImagePath),
      page2ImageBytes: (clearPage2 || clearPage2Image) ? null : (page2ImageBytes ?? this.page2ImageBytes),
      page2ImagePath: (clearPage2 || clearPage2Image) ? null : (page2ImagePath ?? this.page2ImagePath),
      offlineQueue: offlineQueue ?? this.offlineQueue,
      isOfflineModeDetected: isOfflineModeDetected ?? this.isOfflineModeDetected,
      activeInspectionPage: activeInspectionPage ?? this.activeInspectionPage,
      engineMode: engineMode ?? this.engineMode,
      errorMessage: errorMessage,
      successMessage: successMessage,
      committedPatient: committedPatient ?? this.committedPatient,
      duplicateResult: duplicateResult ?? this.duplicateResult,
      isPatientIdConflict: clearPatientIdConflict ? false : (isPatientIdConflict ?? this.isPatientIdConflict),
      patientIdConflictReason: clearPatientIdConflict ? null : (patientIdConflictReason ?? this.patientIdConflictReason),
      activeArchiveItemId: (clearReviewContext || clearActiveArchiveItem)
          ? null
          : (activeArchiveItemId ?? this.activeArchiveItemId),
      reviewingPatientUuid: clearReviewContext ? null : (reviewingPatientUuid ?? this.reviewingPatientUuid),
      reviewingVisitId: clearReviewContext ? null : (reviewingVisitId ?? this.reviewingVisitId),
    );
  }
}

class OcrScanViewModel extends StateNotifier<OcrScanState> {
  final IOcrRepository _repository;
  final IPatientRepository _patientRepository;
  final DocumentCaptureService _captureService;
  String? _scopedCampId;

  OcrScanViewModel({
    IOcrRepository? repository,
    IPatientRepository? patientRepository,
    DocumentCaptureService? captureService,
  })  : _repository = repository ?? OcrRepository(),
        _patientRepository = patientRepository ?? PatientRepository(),
        _captureService = captureService ?? DocumentCaptureService(),
        super(OcrScanState(engineMode: _loadInitialEngineMode())) {
    loadOfflineQueue();
  }

  static OcrEngineMode _loadInitialEngineMode() {
    return OcrEngineMode.onlineGemini;
  }

  Future<void> setEngineMode(OcrEngineMode mode) async {
    state = state.copyWith(engineMode: OcrEngineMode.onlineGemini);
  }

  /// Loads queued offline scans from SQLite (scoped to [campId] when supplied).
  Future<void> loadOfflineQueue({String? campId}) async {
    if (campId != null) {
      _scopedCampId = campId.isEmpty ? null : campId;
    }
    try {
      final items = await _repository.getOfflineScanQueue(campId: _scopedCampId);
      if (!mounted) return;
      state = state.copyWith(offlineQueue: items);
    } catch (_) {}
  }

  /// Saves currently captured/picked Page 1 and/or Page 2 images to local SQLite offline queue
  Future<OfflineScanQueueItem?> saveCurrentScanOffline({
    required String campId,
    required String campCode,
    required String userId,
    required String userName,
    required String userRole,
    required String deviceId,
    String? patientTokenHint,
    String? patientIdHint,
    String? intakeDateHint,
    String? examiningNurseHint,
    String? examiningDoctorHint,
  }) async {
    if (!state.hasAnyCapturedImage) {
      state = state.copyWith(errorMessage: 'Please capture or select at least one Yellow Form image first.');
      return null;
    }
    state = state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    try {
      final item = await _repository.enqueueOfflineScan(
        campId: campId,
        campCode: campCode,
        page1Bytes: state.page1ImageBytes,
        page1Path: state.page1ImagePath ?? state.page1Scan?.imagePath,
        page2Bytes: state.page2ImageBytes,
        page2Path: state.page2ImagePath ?? state.page2Scan?.imagePath,
        patientTokenHint: patientTokenHint ?? patientIdHint,
        intakeDateHint: intakeDateHint,
        examiningNurseHint: examiningNurseHint,
        examiningDoctorHint: examiningDoctorHint,
        userId: userId,
        userName: userName,
        userRole: userRole,
        deviceId: deviceId,
      );
      final updatedQueue = await _repository.getOfflineScanQueue(campId: _scopedCampId ?? campId);
      if (!mounted) return item;
      state = OcrScanState(
        offlineQueue: updatedQueue,
        successMessage: 'Offline scan saved to local storage! It will automatically extract & sync once Internet connects.',
      );
      return item;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save offline scan locally: $e',
      );
      return null;
    }
  }

  /// Deletes a queued offline scan item from SQLite
  Future<void> deleteOfflineQueueItem(String id) async {
    try {
      await _repository.deleteOfflineScanQueueItem(id);
      await loadOfflineQueue();
    } catch (_) {}
  }

  /// Granularly deletes Page 1, Page 2, or all stored Yellow Form photos for a scan
  /// without deleting the committed patient or clinical visit record.
  Future<void> deleteScanPhoto(String id, {int? pageNumber}) async {
    try {
      await _repository.deleteScanPhoto(id, pageNumber: pageNumber);
      final updatedQueue = await _repository.getOfflineScanQueue(campId: _scopedCampId);
      if (!mounted) return;
      if (state.activeArchiveItemId == id) {
        if (pageNumber == 1) {
          final remainingP2Path = state.page2ImagePath ?? state.scanResult?.page2ImagePath;
          state = state.copyWith(
            offlineQueue: updatedQueue,
            clearPage1Image: true,
            page1Scan: state.page1Scan?.copyWith(clearImagePath: true, clearPage1ImagePath: true),
            scanResult: state.scanResult?.copyWith(
              clearPage1ImagePath: true,
              imagePath: remainingP2Path,
              clearImagePath: remainingP2Path == null || remainingP2Path.isEmpty,
            ),
            activeInspectionPage: state.hasPage2Image ? 2 : 1,
            successMessage:
                'Page 1 photo deleted. The patient & visit record remains intact.',
          );
          return;
        } else if (pageNumber == 2) {
          final remainingP1Path = state.page1ImagePath ?? state.scanResult?.page1ImagePath;
          state = state.copyWith(
            offlineQueue: updatedQueue,
            clearPage2Image: true,
            page2Scan: state.page2Scan?.copyWith(clearImagePath: true, clearPage2ImagePath: true),
            scanResult: state.scanResult?.copyWith(
              clearPage2ImagePath: true,
              imagePath: remainingP1Path,
              clearImagePath: remainingP1Path == null || remainingP1Path.isEmpty,
            ),
            activeInspectionPage: state.hasPage1Image ? 1 : 2,
            successMessage:
                'Page 2 photo deleted. The patient & visit record remains intact.',
          );
          return;
        } else {
          state = state.copyWith(
            offlineQueue: updatedQueue,
            clearPage1Image: true,
            clearPage2Image: true,
            clearActiveArchiveItem: true,
            page1Scan: state.page1Scan?.copyWith(clearImagePath: true, clearPage1ImagePath: true),
            page2Scan: state.page2Scan?.copyWith(clearImagePath: true, clearPage2ImagePath: true),
            scanResult: state.scanResult?.copyWith(
              clearImagePath: true,
              clearPage1ImagePath: true,
              clearPage2ImagePath: true,
            ),
            successMessage:
                'All stored scan photos deleted. The patient & visit record remains intact.',
          );
          return;
        }
      }
      state = state.copyWith(
        offlineQueue: updatedQueue,
        successMessage: pageNumber != null
            ? 'Page $pageNumber photo deleted. The committed patient record remains intact.'
            : 'Scanned form photo(s) deleted. The committed patient record remains intact.',
      );
    } catch (_) {}
  }

  /// Deletes all completed Yellow Form scan photos in the archive for the scoped
  /// camp without deleting pending offline scans or committed patient/visit records.
  Future<int> deleteAllScanPhotos({String? campId}) async {
    try {
      final targetCampId = campId ?? _scopedCampId;
      final deletedCount = await _repository.deleteAllScanPhotos(campId: targetCampId);
      final updatedQueue = await _repository.getOfflineScanQueue(campId: _scopedCampId);
      if (!mounted) return deletedCount;
      final activeItemRemoved = state.activeArchiveItemId != null &&
          !updatedQueue.any((i) => i.id == state.activeArchiveItemId);
      state = state.copyWith(
        offlineQueue: updatedQueue,
        clearPage1Image: activeItemRemoved,
        clearPage2Image: activeItemRemoved,
        clearActiveArchiveItem: activeItemRemoved,
        page1Scan: activeItemRemoved
            ? state.page1Scan?.copyWith(clearImagePath: true, clearPage1ImagePath: true)
            : null,
        page2Scan: activeItemRemoved
            ? state.page2Scan?.copyWith(clearImagePath: true, clearPage2ImagePath: true)
            : null,
        scanResult: activeItemRemoved
            ? state.scanResult?.copyWith(
                clearImagePath: true,
                clearPage1ImagePath: true,
                clearPage2ImagePath: true,
              )
            : null,
        successMessage: deletedCount > 0
            ? 'Deleted stored scan photos for $deletedCount record(s). Committed patient & visit records remain intact.'
            : 'No stored scan photos to delete.',
      );
      return deletedCount;
    } catch (_) {
      return 0;
    }
  }

  /// Opens an already-committed or archived Yellow Form scan (Page 1 & Page 2 photos +
  /// cached extracted fields) in split-screen mode for review and correction.
  Future<bool> openArchivedScanForReview(OfflineScanQueueItem item) async {
    final p1Bytes = item.page1Bytes;
    final p2Bytes = item.page2Bytes;
    final cachedResult = item.parsedExtractedResult;

    if (cachedResult != null) {
      String? resolvedPatientUuid = item.committedPatientUuid;
      String? resolvedVisitId = item.committedVisitId;

      if (resolvedVisitId == null || resolvedVisitId.isEmpty) {
        try {
          final latestVisit = await _patientRepository.getLatestClinicalVisit(
            item.committedPatientId ?? item.patientIdHint ?? '',
            patientUuid: resolvedPatientUuid,
          );
          resolvedVisitId = latestVisit?.id;
        } catch (_) {}
      }

      if (!mounted) return true;
      state = state.copyWith(
        isProcessing: false,
        isOfflineModeDetected: false,
        page1ImageBytes: p1Bytes,
        page1ImagePath: item.page1ImagePath,
        page2ImageBytes: p2Bytes,
        page2ImagePath: item.page2ImagePath,
        clearPage1Image: p1Bytes == null || p1Bytes.isEmpty,
        clearPage2Image: p2Bytes == null || p2Bytes.isEmpty,
        page1Scan: item.hasPage1 ? cachedResult : null,
        page2Scan: item.hasPage2 ? cachedResult : null,
        clearPage1: !item.hasPage1,
        clearPage2: !item.hasPage2,
        scanResult: cachedResult,
        activeInspectionPage: item.hasPage1 ? 1 : 2,
        activeArchiveItemId: item.id,
        reviewingPatientUuid: resolvedPatientUuid,
        reviewingVisitId: resolvedVisitId,
        duplicateResult: const DuplicateCheckResult.none(),
        clearPatientIdConflict: true,
        errorMessage: null,
        successMessage:
            'Loaded stored Yellow Form scan for review & correction. Saving will update the existing patient record.',
      );
      return true;
    }

    return processSingleOfflineQueueItem(item);
  }

  /// Loads a queued offline scan into the preview/verification slots and attempts Gemini Cloud OCR
  Future<bool> processSingleOfflineQueueItem(OfflineScanQueueItem item) async {
    Uint8List? p1Bytes;
    if (item.page1ImageBase64 != null && item.page1ImageBase64!.isNotEmpty) {
      try {
        p1Bytes = base64Decode(item.page1ImageBase64!);
      } catch (_) {}
    }
    Uint8List? p2Bytes;
    if (item.page2ImageBase64 != null && item.page2ImageBase64!.isNotEmpty) {
      try {
        p2Bytes = base64Decode(item.page2ImageBase64!);
      } catch (_) {}
    }

    state = state.copyWith(
      isProcessing: true,
      processingStep: 'Processing queued offline scan...',
      page1ImageBytes: p1Bytes,
      page1ImagePath: item.page1ImagePath,
      page2ImageBytes: p2Bytes,
      page2ImagePath: item.page2ImagePath,
      activeArchiveItemId: item.id,
      reviewingPatientUuid: item.committedPatientUuid,
      reviewingVisitId: item.committedVisitId,
      errorMessage: null,
      successMessage: null,
    );
    try {
      final extracted = await _repository.extractQueuedOfflineItem(item);
      final updatedQueue = await _repository.getOfflineScanQueue(campId: _scopedCampId);
      if (!mounted) return true;
      state = state.copyWith(
        isProcessing: false,
        isOfflineModeDetected: false,
        offlineQueue: updatedQueue,
        page1Scan: item.hasPage1 ? extracted : null,
        page2Scan: item.hasPage2 ? extracted : null,
        scanResult: extracted,
        activeArchiveItemId: item.id,
        reviewingPatientUuid: item.committedPatientUuid,
        reviewingVisitId: item.committedVisitId,
        successMessage: 'Queued offline scan extracted! Review & commit below.',
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Cannot process offline scan yet (check Internet connection): ${e is GeminiOcrException ? e.message : e}',
      );
      return false;
    }
  }

  /// Processes and auto-commits all pending offline scans when Internet connectivity is available
  Future<int> syncAllOfflineScans({
    String? defaultUserId,
    String? defaultUserName,
    String? defaultUserRole,
    String? defaultDeviceId,
  }) async {
    state = state.copyWith(
      isProcessing: true,
      processingStep: 'Syncing & extracting queued offline scans...',
      errorMessage: null,
      successMessage: null,
    );
    try {
      final count = await _repository.syncAndProcessAllOfflineScans(
        defaultUserId: defaultUserId,
        defaultUserName: defaultUserName,
        defaultUserRole: defaultUserRole,
        defaultDeviceId: defaultDeviceId,
      );
      final updatedQueue = await _repository.getOfflineScanQueue(campId: _scopedCampId);
      if (!mounted) return count;
      state = state.copyWith(
        isProcessing: false,
        isOfflineModeDetected: false,
        offlineQueue: updatedQueue,
        successMessage: count > 0
            ? '$count offline scan(s) extracted and committed to camp database!'
            : 'No offline scans were processed (check Internet connection).',
      );
      return count;
    } catch (e) {
      if (!mounted) return 0;
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Offline scan sync failed: $e',
      );
      return 0;
    }
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
    state = state.copyWith(errorMessage: null);
    try {
      final photo = await _captureService.scanSingleDocumentPage();
      if (photo == null) {
        return; // user cancelled — nothing to do
      }
      final rawBytes = await photo.readAsBytes();
      if (!mounted) return;
      state = state.copyWith(
        isProcessing: true,
        page1ImageBytes: pageNumber == 1 ? rawBytes : state.page1ImageBytes,
        page1ImagePath: pageNumber == 1 ? photo.path : state.page1ImagePath,
        page2ImageBytes: pageNumber == 2 ? rawBytes : state.page2ImageBytes,
        page2ImagePath: pageNumber == 2 ? photo.path : state.page2ImagePath,
        processingStep: 'Digitizing Page $pageNumber (${pageNumber == 1 ? "Demographics & Obstetric History" : "POP Exam & Vitals"})...',
      );
      final result = await _repository.processImageScan(photo, pageNumber: pageNumber, engineMode: OcrEngineMode.onlineGemini);
      if (!mounted) return;
      if (pageNumber == 1) {
        state = state.copyWith(
          isProcessing: false,
          isOfflineModeDetected: false,
          page1Scan: result,
          successMessage: 'Page 1 (Front) captured successfully. Capture Page 2 or tap Review.',
        );
      } else {
        state = state.copyWith(
          isProcessing: false,
          isOfflineModeDetected: false,
          page2Scan: result,
          successMessage: 'Page 2 (Back) captured successfully. Both pages ready for review.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final isOffline = e is GeminiOcrException || msg.contains('Cannot reach') || msg.contains('SocketException') || msg.contains('timed out');
      final friendlyMsg = msg.contains('camera_access_denied') || msg.contains('permission')
          ? 'Camera permission was denied. Please grant camera permission or use "Upload File".'
          : isOffline
              ? 'Offline mode: Page $pageNumber image captured! Tap "Save Offline Scan Locally" below to store on local storage and auto-sync when Internet connects.'
              : 'Camera capture error: $msg';
      state = state.copyWith(
        isProcessing: false,
        isOfflineModeDetected: isOffline ? true : state.isOfflineModeDetected,
        errorMessage: isOffline ? null : friendlyMsg,
        successMessage: isOffline ? friendlyMsg : state.successMessage,
      );
    }
  }

  /// Legacy single camera capture
  Future<void> captureWithCamera() => capturePage(1);

  /// Picks image for specific page slot (1 or 2)
  Future<void> pickPage(int pageNumber) async {
    state = state.copyWith(errorMessage: null);
    try {
      final photo = await _captureService.pickFromGallery();
      if (photo == null) {
        return; // user cancelled — nothing to do
      }
      final rawBytes = await photo.readAsBytes();
      if (!mounted) return;
      state = state.copyWith(
        isProcessing: true,
        page1ImageBytes: pageNumber == 1 ? rawBytes : state.page1ImageBytes,
        page1ImagePath: pageNumber == 1 ? photo.path : state.page1ImagePath,
        page2ImageBytes: pageNumber == 2 ? rawBytes : state.page2ImageBytes,
        page2ImagePath: pageNumber == 2 ? photo.path : state.page2ImagePath,
        processingStep: 'Digitizing Page $pageNumber (${pageNumber == 1 ? "Demographics & Obstetric History" : "POP Exam & Vitals"})...',
      );
      final result = await _repository.processImageScan(photo, pageNumber: pageNumber, engineMode: OcrEngineMode.onlineGemini);
      if (!mounted) return;
      if (pageNumber == 1) {
        state = state.copyWith(
          isProcessing: false,
          isOfflineModeDetected: false,
          page1Scan: result,
          successMessage: 'Page 1 (Front) imported successfully. Import Page 2 or tap Review.',
        );
      } else {
        state = state.copyWith(
          isProcessing: false,
          isOfflineModeDetected: false,
          page2Scan: result,
          successMessage: 'Page 2 (Back) imported successfully. Both pages ready for review.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final isOffline = e is GeminiOcrException || msg.contains('Cannot reach') || msg.contains('SocketException') || msg.contains('timed out');
      state = state.copyWith(
        isProcessing: false,
        isOfflineModeDetected: isOffline ? true : state.isOfflineModeDetected,
        errorMessage: isOffline ? null : 'Image pick error: $msg',
        successMessage: isOffline
            ? 'Offline mode: Page $pageNumber image loaded! Tap "Save Offline Scan Locally" below to store on local storage and auto-sync when Internet connects.'
            : state.successMessage,
      );
    }
  }

  /// Legacy single gallery picker
  Future<void> pickFromGallery() => pickPage(1);

  /// Selects both Page 1 and Page 2 at once via multi-image picker
  Future<void> pickBothPages() async {
    state = state.copyWith(errorMessage: null);
    try {
      final photos = await _captureService.pickMultipleImages();
      if (photos.isEmpty) {
        return; // user cancelled — nothing to do
      }
      final bytes1 = await photos[0].readAsBytes();
      final bytes2 = photos.length > 1 ? await photos[1].readAsBytes() : null;
      if (!mounted) return;
      state = state.copyWith(
        isProcessing: true,
        page1ImageBytes: bytes1,
        page1ImagePath: photos[0].path,
        page2ImageBytes: bytes2 ?? state.page2ImageBytes,
        page2ImagePath: photos.length > 1 ? photos[1].path : state.page2ImagePath,
        processingStep: 'Digitizing Page 1 of 2 (Demographics & Obstetric History)...',
      );
      if (photos.length == 1) {
        final res = await _repository.processImageScan(photos[0], pageNumber: 1, engineMode: OcrEngineMode.onlineGemini);
        if (!mounted) return;
        state = state.copyWith(
          isProcessing: false,
          isOfflineModeDetected: false,
          page1Scan: res,
          successMessage: '1 document page imported. Import Page 2 or tap Review.',
        );
        return;
      }

      final res1 = await _repository.processImageScan(photos[0], pageNumber: 1, engineMode: OcrEngineMode.onlineGemini);
      if (!mounted) return;
      state = state.copyWith(
        processingStep: 'Page 1 complete! Digitizing Page 2 of 2 (POP Exam & Vitals)...',
      );
      final res2 = await _repository.processImageScan(photos[1], pageNumber: 2, engineMode: OcrEngineMode.onlineGemini);
      if (!mounted) return;
      state = state.copyWith(
        processingStep: 'Merging clinical stations & checking records...',
      );
      final merged = OcrScanResultModel.merge(res1, res2);

      state = state.copyWith(
        isProcessing: false,
        isOfflineModeDetected: false,
        page1Scan: res1,
        page2Scan: res2,
        scanResult: merged,
        successMessage: 'Both Page 1 (Front) & Page 2 (Back) successfully imported & merged!',
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final isOffline = e is GeminiOcrException || msg.contains('Cannot reach') || msg.contains('SocketException') || msg.contains('timed out');
      state = state.copyWith(
        isProcessing: false,
        isOfflineModeDetected: isOffline ? true : state.isOfflineModeDetected,
        errorMessage: isOffline ? null : 'Multi-image pick error: $msg',
        successMessage: isOffline
            ? 'Offline mode: Scanned form images loaded! Tap "Save Offline Scan Locally" below to store on local storage and auto-sync when Internet connects.'
            : state.successMessage,
      );
    }
  }

  /// Scans both Page 1 and Page 2 in a unified edge-detecting document scanner session
  Future<void> scanBothPagesWithDocumentScanner() async {
    state = state.copyWith(errorMessage: null);
    try {
      final photos = await _captureService.scanDocumentPages(pageLimit: 2);
      if (photos.isEmpty) return;
      final bytes1 = await photos[0].readAsBytes();
      final bytes2 = photos.length > 1 ? await photos[1].readAsBytes() : null;
      if (!mounted) return;

      state = state.copyWith(
        isProcessing: true,
        page1ImageBytes: bytes1,
        page1ImagePath: photos[0].path,
        page2ImageBytes: bytes2 ?? state.page2ImageBytes,
        page2ImagePath: photos.length > 1 ? photos[1].path : state.page2ImagePath,
        processingStep: 'Digitizing Page 1 of 2 (Demographics & Obstetric History)...',
      );
      if (photos.length == 1) {
        final res = await _repository.processImageScan(photos[0], pageNumber: 1, engineMode: OcrEngineMode.onlineGemini);
        if (!mounted) return;
        state = state.copyWith(
          isProcessing: false,
          isOfflineModeDetected: false,
          page1Scan: res,
          successMessage: 'Page 1 scanned and rectified. Capture Page 2 or tap Review.',
        );
        return;
      }

      final res1 = await _repository.processImageScan(photos[0], pageNumber: 1, engineMode: OcrEngineMode.onlineGemini);
      if (!mounted) return;
      state = state.copyWith(
        processingStep: 'Page 1 complete! Digitizing Page 2 of 2 (POP Exam & Vitals)...',
      );
      final res2 = await _repository.processImageScan(photos[1], pageNumber: 2, engineMode: OcrEngineMode.onlineGemini);
      if (!mounted) return;
      state = state.copyWith(
        processingStep: 'Merging clinical stations & checking records...',
      );
      final merged = OcrScanResultModel.merge(res1, res2);

      state = state.copyWith(
        isProcessing: false,
        isOfflineModeDetected: false,
        page1Scan: res1,
        page2Scan: res2,
        scanResult: merged,
        successMessage: 'Both Page 1 (Front) & Page 2 (Back) scanned, deskewed & merged!',
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final isOffline = e is GeminiOcrException || msg.contains('Cannot reach') || msg.contains('SocketException') || msg.contains('timed out');
      state = state.copyWith(
        isProcessing: false,
        isOfflineModeDetected: isOffline ? true : state.isOfflineModeDetected,
        errorMessage: isOffline ? null : 'Document scanner error: $msg',
        successMessage: isOffline
            ? 'Offline mode: Scanned form images ready! Tap "Save Offline Scan Locally" below to store on local storage and auto-sync when Internet connects.'
            : state.successMessage,
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

  /// Returns from verification pane to the dual-slot capture screen.
  /// When exiting Review & Correction Mode for an already-committed archived scan,
  /// resets the review state cleanly so Page 1 & Page 2 slots return empty for a new scan.
  /// During an active uncommitted capture, preserves captured slots so the user can
  /// upload or retake the other page without losing work.
  void returnToCaptureSlots() {
    if (state.isReviewingCommittedScan) {
      resetScan();
      return;
    }
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
    if (key == 'patientId' || key == 'patientTokenId') {
      updatedDemo['patientId'] = value;
      updatedDemo['patientTokenId'] = value;
    }
    String? updatedIntake = state.scanResult!.intakeDate;
    if (key == 'intakeDate' || key == 'date') {
      final cleanDate = value?.toString().trim();
      updatedIntake = (cleanDate != null && cleanDate.isNotEmpty) ? cleanDate : null;
      updatedDemo['intakeDate'] = updatedIntake;
      updatedDemo['date'] = updatedIntake;
    }
    state = state.copyWith(
      scanResult: state.scanResult!.copyWith(
        demographics: updatedDemo,
        intakeDate: updatedIntake,
        clearIntakeDate: (key == 'intakeDate' || key == 'date') && updatedIntake == null,
      ),
    );
    if (key == 'patientId' || key == 'patientTokenId') {
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
    final existing = await _patientRepository.getPatientByPatientId(target);
    if (!mounted) return;
    final isOwnRecord = existing != null &&
        state.reviewingPatientUuid != null &&
        state.reviewingPatientUuid!.isNotEmpty &&
        existing.id == state.reviewingPatientUuid;
    final isTaken = !isOwnRecord &&
        (existing != null || await _patientRepository.isPatientIdTaken(target));
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
      excludePatientUuid: state.reviewingPatientUuid,
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
    } else if (key == 'anteriorStage' || key == 'middleStage' || key == 'posteriorStage') {
      // Recalculate highest if anterior, middle, or posterior wall changed
      final ant = updatedPop['anteriorStage'] as int?;
      final mid = updatedPop['middleStage'] as int?;
      final post = updatedPop['posteriorStage'] as int?;
      if (ant != null || mid != null || post != null) {
        final calc = [ant ?? 0, mid ?? 0, post ?? 0].reduce((a, b) => a > b ? a : b);
        updatedPop['highestPopStage'] = calc;
        updatedPop['highestStage'] = calc;
        updatedPop['stage'] = calc;
      } else {
        updatedPop['highestPopStage'] = null;
        updatedPop['highestStage'] = null;
        updatedPop['stage'] = null;
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

  /// Updates follow-up hospital name dynamically
  void updateFollowUpHospitalName(String? hospitalName) {
    if (state.scanResult == null) return;
    final clean = hospitalName?.trim();
    final effectiveDest = (clean != null && clean.isNotEmpty) ? clean : 'Hospital';
    updateFollowUpDestination(effectiveDest);
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

    // Find existing item from complaint or any alias
    Map<String, dynamic> findExisting() {
      if (details.containsKey(complaint)) return Map<String, dynamic>.from(details[complaint] as Map? ?? {});
      final lk = complaint.toLowerCase().trim();
      if (details.containsKey(lk)) return Map<String, dynamic>.from(details[lk] as Map? ?? {});
      final sp = lk.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
      if (details.containsKey(sp)) return Map<String, dynamic>.from(details[sp] as Map? ?? {});
      final us = lk.replaceAll(RegExp(r'[\s\-]+'), '_').trim();
      if (details.containsKey(us)) return Map<String, dynamic>.from(details[us] as Map? ?? {});
      for (final entry in details.entries) {
        final ek = entry.key.toLowerCase().trim();
        if ((ek.contains('prolapse') || ek.contains('hanging')) && (lk.contains('prolapse') || lk.contains('hanging'))) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if ((ek.contains('urine') || ek.contains('micturition')) && (lk.contains('urine') || lk.contains('micturition'))) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
        if ((ek.contains('discharge') || ek.contains('itching')) && (lk.contains('discharge') || lk.contains('itching'))) {
          return Map<String, dynamic>.from(entry.value as Map? ?? {});
        }
      }
      return {};
    }

    final item = findExisting();
    if (duration != null) item['duration'] = duration;
    if (remarks != null) item['remarks'] = remarks;
    if (subOption != null) {
      if (subOption is List) {
        item['subOption'] = subOption.join(', ');
        item['subOptions'] = subOption;
        item['options'] = subOption;
      } else {
        item['subOption'] = subOption.toString();
        item['subOptions'] = subOption.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        item['options'] = item['subOptions'];
      }
    }

    // Mirror to all aliases
    final lowerC = complaint.toLowerCase().trim();
    final withSpaces = lowerC.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    final withUnderscores = lowerC.replaceAll(RegExp(r'[\s\-]+'), '_').trim();
    final aliases = <String>{complaint, lowerC, withSpaces, withUnderscores};
    if (lowerC.contains('hanging') || lowerC.contains('prolapse')) {
      aliases.addAll(['prolapse', 'something hanging out', 'something_hanging_out']);
    } else if (lowerC.contains('discharge') || lowerC.contains('itching')) {
      aliases.addAll(['discharge', 'discharge and or itching', 'discharge_and_or_itching', 'discharge / itching', 'discharge___itching', 'discharge_itching']);
    } else if (lowerC.contains('urine') || lowerC.contains('micturition')) {
      aliases.addAll(['urine', 'problems passing urine', 'problems_passing_urine']);
    } else if (lowerC.contains('stool') || lowerC.contains('bowel')) {
      aliases.addAll(['stool', 'problems passing stool', 'problems_passing_stool']);
    } else if (lowerC.contains('menstrual')) {
      aliases.addAll(['menstrual', 'menstrual problem', 'menstrual_problem']);
    } else if (lowerC.contains('infertility')) {
      aliases.addAll(['infertility']);
    } else if (lowerC.contains('abdomen')) {
      aliases.addAll(['lower_abdomen_pain', 'lower abdomen pain', 'pain']);
    } else if (lowerC.contains('back')) {
      aliases.addAll(['lower_back_pain', 'lower back pain', 'pain']);
    } else if (lowerC == 'pain') {
      aliases.addAll(['pain', 'lower_abdomen_pain', 'lower_back_pain']);
    } else if (lowerC.contains('checkup')) {
      aliases.addAll(['checkup']);
    }

    for (final a in aliases) {
      details[a] = Map<String, dynamic>.from(item);
    }
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
      'anamnesisDate' => state.scanResult!.copyWith(
          anamnesisDate: clean,
          clearAnamnesisDate: clean == null,
          demographics: {
            ...state.scanResult!.demographics,
            'anamnesisDate': clean,
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

  /// Synchronizes all 6 station dates simultaneously
  void syncAllStationDates(String? dateStr) {
    if (state.scanResult == null) return;
    final clean = (dateStr == null || dateStr.trim().isEmpty) ? null : dateStr.trim();
    final updated = state.scanResult!.copyWith(
      intakeDate: clean,
      clearIntakeDate: clean == null,
      anamnesisDate: clean,
      clearAnamnesisDate: clean == null,
      examDate: clean,
      clearExamDate: clean == null,
      treatmentDate: clean,
      clearTreatmentDate: clean == null,
      conclusionDate: clean,
      clearConclusionDate: clean == null,
      labTestDate: clean,
      clearLabTestDate: clean == null,
      outtakeDate: clean,
      clearOuttakeDate: clean == null,
      demographics: {
        ...state.scanResult!.demographics,
        'intakeDate': clean,
        'date': clean,
      },
    );
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
        existingPatientUuid: state.reviewingPatientUuid,
        existingVisitId: state.reviewingVisitId,
        archiveItemId: state.activeArchiveItemId,
        page1ImageBytes: state.page1ImageBytes,
        page1ImagePath: state.isReviewingCommittedScan
            ? state.page1ImagePath
            : (state.page1ImagePath ?? state.page1Scan?.imagePath),
        page2ImageBytes: state.page2ImageBytes,
        page2ImagePath: state.isReviewingCommittedScan
            ? state.page2ImagePath
            : (state.page2ImagePath ?? state.page2Scan?.imagePath),
        reviewStatus: 'verified',
        preservePhotoArchive: true,
      );

      if (!mounted) return savedPatient;
      state = state.copyWith(
        isSaving: false,
        committedPatient: savedPatient,
        reviewingPatientUuid: savedPatient.id,
        successMessage: 'Patient ${savedPatient.patientId} verified & saved directly to local database!',
      );
      unawaited(loadOfflineQueue(campId: campId));
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

  /// Clears state to start a new scan while keeping offlineQueue loaded
  void resetScan() {
    state = OcrScanState(offlineQueue: state.offlineQueue);
  }
}

final ocrRepositoryProvider = Provider<IOcrRepository>((ref) {
  return OcrRepository();
});

final ocrScanProvider = StateNotifierProvider<OcrScanViewModel, OcrScanState>((ref) {
  return OcrScanViewModel(repository: ref.watch(ocrRepositoryProvider));
});
