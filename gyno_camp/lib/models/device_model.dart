import '../core/constants/app_constants.dart';

enum DeviceActivationStatus {
  unregistered,
  pendingOtp,
  pendingApproval,
  approved,
  revoked;

  static DeviceActivationStatus fromString(String status) {
    switch (status.toUpperCase()) {
      case AppConstants.deviceStatusPendingOtp:
        return DeviceActivationStatus.pendingOtp;
      case AppConstants.deviceStatusPendingApproval:
        return DeviceActivationStatus.pendingApproval;
      case AppConstants.deviceStatusApproved:
        return DeviceActivationStatus.approved;
      case AppConstants.deviceStatusRevoked:
        return DeviceActivationStatus.revoked;
      case AppConstants.deviceStatusUnregistered:
      default:
        return DeviceActivationStatus.unregistered;
    }
  }

  String toDbString() {
    switch (this) {
      case DeviceActivationStatus.unregistered:
        return AppConstants.deviceStatusUnregistered;
      case DeviceActivationStatus.pendingOtp:
        return AppConstants.deviceStatusPendingOtp;
      case DeviceActivationStatus.pendingApproval:
        return AppConstants.deviceStatusPendingApproval;
      case DeviceActivationStatus.approved:
        return AppConstants.deviceStatusApproved;
      case DeviceActivationStatus.revoked:
        return AppConstants.deviceStatusRevoked;
    }
  }

  String get displayNameEn {
    switch (this) {
      case DeviceActivationStatus.unregistered:
        return 'Unregistered';
      case DeviceActivationStatus.pendingOtp:
        return 'OTP Verification Required';
      case DeviceActivationStatus.pendingApproval:
        return 'Pending Admin Approval';
      case DeviceActivationStatus.approved:
        return 'Approved & Active';
      case DeviceActivationStatus.revoked:
        return 'Revoked';
    }
  }
}

class DeviceModel {
  final String deviceId;
  final String deviceName;
  final String model;
  final String hardwareFingerprint;
  final DeviceActivationStatus status;
  final String? registeredByUserId;
  final String? registeredByName;
  final String? otpHash;
  final DateTime? otpExpiresAt;
  final DateTime registeredAt;
  final DateTime? approvedAt;
  final String? approvedByUserId;
  final String? pinHash; // Hashed local app lock PIN

  const DeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.model,
    required this.hardwareFingerprint,
    this.status = DeviceActivationStatus.unregistered,
    this.registeredByUserId,
    this.registeredByName,
    this.otpHash,
    this.otpExpiresAt,
    required this.registeredAt,
    this.approvedAt,
    this.approvedByUserId,
    this.pinHash,
  });

  bool get isApproved => status == DeviceActivationStatus.approved;
  bool get hasPinSet => pinHash != null && pinHash!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'device_name': deviceName,
      'model': model,
      'hardware_fingerprint': hardwareFingerprint,
      'status': status.toDbString(),
      'registered_by_user_id': registeredByUserId,
      'registered_by_name': registeredByName,
      'otp_hash': otpHash,
      'otp_expires_at': otpExpiresAt?.toIso8601String(),
      'registered_at': registeredAt.toIso8601String(),
      'approved_at': approvedAt?.toIso8601String(),
      'approved_by_user_id': approvedByUserId,
      'pin_hash': pinHash,
    };
  }

  factory DeviceModel.fromMap(Map<String, dynamic> map) {
    return DeviceModel(
      deviceId: map['device_id'] as String,
      deviceName: map['device_name'] as String,
      model: map['model'] as String? ?? 'Android Tablet',
      hardwareFingerprint: map['hardware_fingerprint'] as String,
      status: DeviceActivationStatus.fromString(map['status'] as String? ?? ''),
      registeredByUserId: map['registered_by_user_id'] as String?,
      registeredByName: map['registered_by_name'] as String?,
      otpHash: map['otp_hash'] as String?,
      otpExpiresAt: map['otp_expires_at'] != null
          ? DateTime.tryParse(map['otp_expires_at'] as String)
          : null,
      registeredAt: DateTime.tryParse(map['registered_at'] as String? ?? '') ?? DateTime.now(),
      approvedAt: map['approved_at'] != null
          ? DateTime.tryParse(map['approved_at'] as String)
          : null,
      approvedByUserId: map['approved_by_user_id'] as String?,
      pinHash: map['pin_hash'] as String?,
    );
  }

  DeviceModel copyWith({
    String? deviceId,
    String? deviceName,
    String? model,
    String? hardwareFingerprint,
    DeviceActivationStatus? status,
    String? registeredByUserId,
    String? registeredByName,
    String? otpHash,
    DateTime? otpExpiresAt,
    DateTime? registeredAt,
    DateTime? approvedAt,
    String? approvedByUserId,
    String? pinHash,
  }) {
    return DeviceModel(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      model: model ?? this.model,
      hardwareFingerprint: hardwareFingerprint ?? this.hardwareFingerprint,
      status: status ?? this.status,
      registeredByUserId: registeredByUserId ?? this.registeredByUserId,
      registeredByName: registeredByName ?? this.registeredByName,
      otpHash: otpHash ?? this.otpHash,
      otpExpiresAt: otpExpiresAt ?? this.otpExpiresAt,
      registeredAt: registeredAt ?? this.registeredAt,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedByUserId: approvedByUserId ?? this.approvedByUserId,
      pinHash: pinHash ?? this.pinHash,
    );
  }
}
