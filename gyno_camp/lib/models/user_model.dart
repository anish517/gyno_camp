import '../core/constants/app_constants.dart';

enum UserRole {
  superAdmin,
  dataTaker,
  dataAnalyst;

  static UserRole fromString(String role) {
    switch (role.toUpperCase().replaceAll('_', '')) {
      case 'SUPERADMIN':
        return UserRole.superAdmin;
      case 'DATAANALYST':
        return UserRole.dataAnalyst;
      case 'DATATAKER':
      default:
        return UserRole.dataTaker;
    }
  }

  String toDbString() {
    switch (this) {
      case UserRole.superAdmin:
        return AppConstants.roleSuperAdmin;
      case UserRole.dataTaker:
        return AppConstants.roleDataTaker;
      case UserRole.dataAnalyst:
        return AppConstants.roleDataAnalyst;
    }
  }

  String get displayNameEn {
    switch (this) {
      case UserRole.superAdmin:
        return 'Super Admin';
      case UserRole.dataTaker:
        return 'Data Taker';
      case UserRole.dataAnalyst:
        return 'Data Analyst';
    }
  }

  String get displayNameNe {
    switch (this) {
      case UserRole.superAdmin:
        return 'सुपर एडमिन';
      case UserRole.dataTaker:
        return 'डाटा टेकर (क्षेत्रीय कर्मचारी)';
      case UserRole.dataAnalyst:
        return 'डाटा विश्लेषक';
    }
  }
}

class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final bool isActive;
  final DateTime? lastLoginAt;
  final List<String> assignedCampIds;
  final String tenantId;
  final String tenantName;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.isActive = true,
    this.lastLoginAt,
    this.assignedCampIds = const [],
    this.tenantId = 'tenant_bir_hospital',
    this.tenantName = 'Bir Hospital Gyno Outreach',
  });

  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isDataTaker => role == UserRole.dataTaker;
  bool get isDataAnalyst => role == UserRole.dataAnalyst;

  bool get canManageCamps => isSuperAdmin;
  bool get canApproveDevices => isSuperAdmin;
  bool get canCustomizeDropdowns => isSuperAdmin;
  bool get canEnterClinicalData => isDataTaker || isSuperAdmin;
  bool get canExportReports => isDataAnalyst || isSuperAdmin;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.toDbString(),
      'is_active': isActive ? 1 : 0,
      'last_login_at': lastLoginAt?.toIso8601String(),
      'assigned_camp_ids': assignedCampIds.join(','),
      'tenant_id': tenantId,
      'tenant_name': tenantName,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      phone: map['phone'] as String? ?? '',
      role: UserRole.fromString(map['role'] as String? ?? ''),
      isActive: (map['is_active'] is int)
          ? (map['is_active'] as int) == 1
          : (map['is_active'] as bool? ?? true),
      lastLoginAt: map['last_login_at'] != null
          ? DateTime.tryParse(map['last_login_at'] as String)
          : null,
      assignedCampIds: map['assigned_camp_ids'] != null && (map['assigned_camp_ids'] as String).isNotEmpty
          ? (map['assigned_camp_ids'] as String).split(',')
          : [],
      tenantId: map['tenant_id'] as String? ?? 'tenant_bir_hospital',
      tenantName: map['tenant_name'] as String? ?? 'Bir Hospital Gyno Outreach',
    );
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    bool? isActive,
    DateTime? lastLoginAt,
    List<String>? assignedCampIds,
    String? tenantId,
    String? tenantName,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      assignedCampIds: assignedCampIds ?? this.assignedCampIds,
      tenantId: tenantId ?? this.tenantId,
      tenantName: tenantName ?? this.tenantName,
    );
  }
}
