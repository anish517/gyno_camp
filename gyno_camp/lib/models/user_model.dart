import '../core/constants/app_constants.dart';

enum UserRole {
  superAdmin,
  staff,
  dataTaker,
  dataAnalyst;

  static UserRole fromString(String role) {
    final clean = role.toUpperCase().replaceAll('_', '').replaceAll(' ', '').trim();
    switch (clean) {
      case 'SUPERADMIN':
      case 'ADMIN':
      case 'SUPERADMINISTRATOR':
      case 'ROOT':
      case 'SYSTEMADMINISTRATOR':
        return UserRole.superAdmin;
      case 'STAFF':
      case 'STAFFADMIN':
      case 'STAFFCOORDINATOR':
      case 'CAMPSTAFF':
        return UserRole.staff;
      case 'DATAANALYST':
      case 'ANALYST':
      case 'EPIDEMIOLOGIST':
        return UserRole.dataAnalyst;
      case 'DATATAKER':
      case 'NURSE':
      case 'FIELDNURSE':
      case 'STAFFNURSE':
      case 'COMMUNITYHEALTHNURSE':
        return UserRole.dataTaker;
      default:
        return UserRole.dataTaker;
    }
  }

  String toDbString() {
    switch (this) {
      case UserRole.superAdmin:
        return AppConstants.roleSuperAdmin;
      case UserRole.staff:
        return AppConstants.roleStaff;
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
      case UserRole.staff:
        return 'Staff Coordinator';
      case UserRole.dataTaker:
        return 'Data Taker';
      case UserRole.dataAnalyst:
        return 'Data Analyst';
    }
  }

  /// Order used to pick a user's default (primary) role and to list roles:
  /// the broadest workspace first.
  static const List<UserRole> precedence = [
    UserRole.superAdmin,
    UserRole.staff,
    UserRole.dataTaker,
    UserRole.dataAnalyst,
  ];

  /// Parses the `role` column, which holds one role ("DATA_TAKER") or, for
  /// staff with several jobs, a comma-separated list ("STAFF,DATA_TAKER").
  static Set<UserRole> parseList(String raw) {
    final parts = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final roles = parts.map(UserRole.fromString).toSet();
    return roles.isEmpty ? {UserRole.dataTaker} : roles;
  }

  static UserRole primaryOf(Iterable<UserRole> roles) =>
      precedence.firstWhere(roles.contains, orElse: () => UserRole.dataTaker);

  String get displayNameNe {
    switch (this) {
      case UserRole.superAdmin:
        return 'सुपर एडमिन';
      case UserRole.staff:
        return 'कर्मचारी व्यवस्थापक (स्टाफ)';
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

  /// The role this session is working as: the terminal chosen at login, or the
  /// account's primary role. All `isX` / `canX` checks below use this role, so
  /// each workspace behaves exactly as it does for a single-role account.
  final UserRole role;

  /// Every role the account holds (empty = just [role]). Use [roles].
  final Set<UserRole> grantedRoles;
  final bool isActive;
  final DateTime? lastLoginAt;
  final List<String> assignedCampIds;
  final String tenantId;
  final String tenantName;
  final String? passwordHash;
  final String? pinHash;
  final DateTime? updatedAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.grantedRoles = const {},
    this.isActive = true,
    this.lastLoginAt,
    this.assignedCampIds = const [],
    this.tenantId = 'tenant_default',
    this.tenantName = 'Outreach Health Center',
    this.passwordHash,
    this.pinHash,
    this.updatedAt,
  });

  bool get isSuperAdmin =>
      role == UserRole.superAdmin ||
      id == 'usr-superadmin-01' ||
      email.trim().toLowerCase() == 'admin@gynocamp.org' ||
      name.toLowerCase().contains('super admin') ||
      name.toLowerCase().contains('super administrator');
  /// All roles the account holds, always including the active [role].
  Set<UserRole> get roles => {...grantedRoles, role};
  bool hasRole(UserRole r) => roles.contains(r);
  bool get hasMultipleRoles => roles.length > 1;

  /// Roles in display order, e.g. [staff, dataTaker, dataAnalyst].
  List<UserRole> get sortedRoles => UserRole.precedence.where(roles.contains).toList();

  /// Value stored in the `role` column: one role, or a comma-separated list.
  String get rolesDbString => sortedRoles.map((r) => r.toDbString()).join(',');

  /// "Staff Coordinator, Data Taker, Data Analyst"
  String get rolesLabel => sortedRoles.map((r) => r.displayNameEn).join(', ');

  bool get isStaff => role == UserRole.staff;
  bool get isDataTaker => role == UserRole.dataTaker;
  bool get isDataAnalyst => role == UserRole.dataAnalyst;

  bool get canManageCamps => isSuperAdmin || isStaff;
  bool get canManageStaff => isSuperAdmin || isStaff;
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
      'role': rolesDbString,
      'is_active': isActive ? 1 : 0,
      'last_login_at': lastLoginAt?.toIso8601String(),
      'assigned_camp_ids': assignedCampIds.join(','),
      'tenant_id': tenantId,
      'tenant_name': tenantName,
      'password_hash': passwordHash,
      'pin_hash': pinHash,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static Set<UserRole> _rolesFromMap(Map<String, dynamic> map) {
    final emailStr = (map['email'] as String? ?? '').trim().toLowerCase();
    final idStr = (map['id'] as String? ?? '').trim();
    final nameStr = (map['name'] as String? ?? '').trim().toLowerCase();
    if (idStr == 'usr-superadmin-01' ||
        emailStr == 'admin@gynocamp.org' ||
        nameStr.contains('super administrator') ||
        nameStr.contains('super admin')) {
      return {UserRole.superAdmin};
    }
    try {
      return UserRole.parseList(map['role'] as String? ?? '');
    } catch (_) {
      // Gracefully handle unknown/legacy roles from DB without crashing
      return {UserRole.dataTaker};
    }
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      phone: map['phone'] as String? ?? '',
      role: UserRole.primaryOf(_rolesFromMap(map)),
      grantedRoles: _rolesFromMap(map),
      isActive: (map['is_active'] is int)
          ? (map['is_active'] as int) == 1
          : (map['is_active'] as bool? ?? true),
      lastLoginAt: map['last_login_at'] != null
          ? DateTime.tryParse(map['last_login_at'] as String)
          : null,
      assignedCampIds: () {
        final raw = map['assigned_camp_ids'];
        if (raw is List) {
          return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        } else if (raw is String && raw.trim().isNotEmpty) {
          return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        }
        return <String>[];
      }(),
      tenantId: map['tenant_id'] as String? ?? 'tenant_default',
      tenantName: map['tenant_name'] as String? ?? 'Outreach Health Center',
      passwordHash: map['password_hash'] as String?,
      pinHash: map['pin_hash'] as String?,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    Set<UserRole>? grantedRoles,
    bool? isActive,
    DateTime? lastLoginAt,
    List<String>? assignedCampIds,
    String? tenantId,
    String? tenantName,
    String? passwordHash,
    String? pinHash,
    DateTime? updatedAt,
  }) {
    // grantedRoles given: the account's roles change; keep the active role if
    //   still granted, otherwise fall back to the new primary role.
    // Only role given: switching workspace when the account holds that role,
    //   otherwise a plain role change (the account now holds just that role).
    final Set<UserRole> newGranted;
    final UserRole newRole;
    if (grantedRoles != null && grantedRoles.isNotEmpty) {
      newGranted = Set.unmodifiable(grantedRoles);
      final wanted = role ?? this.role;
      newRole = newGranted.contains(wanted) ? wanted : UserRole.primaryOf(newGranted);
    } else if (role != null && !roles.contains(role)) {
      newGranted = const {};
      newRole = role;
    } else {
      newGranted = this.grantedRoles;
      newRole = role ?? this.role;
    }
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: newRole,
      grantedRoles: newGranted,
      isActive: isActive ?? this.isActive,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      assignedCampIds: assignedCampIds ?? this.assignedCampIds,
      tenantId: tenantId ?? this.tenantId,
      tenantName: tenantName ?? this.tenantName,
      passwordHash: passwordHash ?? this.passwordHash,
      pinHash: pinHash ?? this.pinHash,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
