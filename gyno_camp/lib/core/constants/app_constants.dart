class AppConstants {
  static const String appName = 'Gynocamp';
  static const String appTitleEn = 'Gynocamp Patient Registration';
  static const String appTitleNe = 'गाइनोकैम्प बिरामी दर्ता प्रणाली';
  static const String appVersion = '1.0.0';
  static const String databaseName = 'gynocamp_offline.db';
  static const int databaseVersion = 1;

  // Roles
  static const String roleSuperAdmin = 'SUPER_ADMIN';
  static const String roleDataTaker = 'DATA_TAKER';
  static const String roleDataAnalyst = 'DATA_ANALYST';

  // Device Statuses
  static const String deviceStatusUnregistered = 'UNREGISTERED';
  static const String deviceStatusPendingOtp = 'PENDING_OTP';
  static const String deviceStatusPendingApproval = 'PENDING_APPROVAL';
  static const String deviceStatusApproved = 'APPROVED';
  static const String deviceStatusRevoked = 'REVOKED';

  // Camp Statuses
  static const String campStatusDraft = 'DRAFT';
  static const String campStatusScheduled = 'SCHEDULED';
  static const String campStatusOpen = 'OPEN';
  static const String campStatusClosed = 'CLOSED';
  static const String campStatusArchived = 'ARCHIVED';

  // Audit Actions
  static const String auditActionLogin = 'USER_LOGIN';
  static const String auditActionLogout = 'USER_LOGOUT';
  static const String auditActionDeviceRegister = 'DEVICE_REGISTER_REQUEST';
  static const String auditActionDeviceApprove = 'DEVICE_APPROVED';
  static const String auditActionDeviceRevoke = 'DEVICE_REVOKED';
  static const String auditActionAppUnlocked = 'APP_UNLOCKED_PIN';
  static const String auditActionCampCreate = 'CAMP_CREATED';
  static const String auditActionCampOpen = 'CAMP_OPENED';
  static const String auditActionCampClose = 'CAMP_CLOSED';
  static const String auditActionPatientRegister = 'PATIENT_REGISTERED';
  static const String auditActionClinicalEntry = 'CLINICAL_ENTRY_SAVED';
  static const String auditActionSyncStarted = 'SYNC_STARTED';
  static const String auditActionSyncCompleted = 'SYNC_COMPLETED';
  static const String auditActionSyncUpload = 'SYNC_UPLOAD_PUSH';
  static const String auditActionSyncDownload = 'SYNC_DOWNLOAD_PULL';
  static const String auditActionReportPdfExport = 'REPORT_PDF_EXPORTED';
  static const String auditActionReportExcelExport = 'REPORT_EXCEL_EXPORTED';
  static const String auditActionFormScannedOcr = 'FORM_SCANNED_OCR';
  static const String auditActionPatientRegisteredViaOcr = 'PATIENT_REGISTERED_VIA_OCR';
}
