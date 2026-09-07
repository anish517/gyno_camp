import '../core/constants/app_constants.dart';

enum CampStatus {
  draft,
  scheduled,
  open,
  closed,
  archived;

  static CampStatus fromString(String status) {
    switch (status.toUpperCase()) {
      case AppConstants.campStatusScheduled:
        return CampStatus.scheduled;
      case AppConstants.campStatusOpen:
        return CampStatus.open;
      case AppConstants.campStatusClosed:
        return CampStatus.closed;
      case AppConstants.campStatusArchived:
        return CampStatus.archived;
      case AppConstants.campStatusDraft:
      default:
        return CampStatus.draft;
    }
  }

  String toDbString() {
    switch (this) {
      case CampStatus.draft:
        return AppConstants.campStatusDraft;
      case CampStatus.scheduled:
        return AppConstants.campStatusScheduled;
      case CampStatus.open:
        return AppConstants.campStatusOpen;
      case CampStatus.closed:
        return AppConstants.campStatusClosed;
      case CampStatus.archived:
        return AppConstants.campStatusArchived;
    }
  }

  String get displayNameEn {
    switch (this) {
      case CampStatus.draft:
        return 'Draft';
      case CampStatus.scheduled:
        return 'Scheduled';
      case CampStatus.open:
        return 'Open for Entry';
      case CampStatus.closed:
        return 'Closed (Camp Finished)';
      case CampStatus.archived:
        return 'Archived';
    }
  }

  bool get isOpenForDataEntry => this == CampStatus.open;
}

class CampModel {
  final String id;
  final String campCode; // e.g., 'KTM01', 'DHN02'
  final String name;
  final String district;
  final String municipality;
  final String ward;
  final String venue;
  final DateTime startDate;
  final DateTime endDate;
  final CampStatus status;
  final List<String> assignedStaffIds;
  final int totalPatientsRegistered;
  final String tenantId;
  final String organizationName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CampModel({
    required this.id,
    required this.campCode,
    required this.name,
    required this.district,
    required this.municipality,
    required this.ward,
    required this.venue,
    required this.startDate,
    required this.endDate,
    this.status = CampStatus.draft,
    this.assignedStaffIds = const [],
    this.totalPatientsRegistered = 0,
    this.tenantId = 'tenant_bir_hospital',
    this.organizationName = 'Bir Hospital Gyno Outreach',
    required this.createdAt,
    this.updatedAt,
  });

  bool get isOpen => status == CampStatus.open;
  bool isStaffAssigned(String userId) => assignedStaffIds.contains(userId);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'camp_code': campCode,
      'name': name,
      'district': district,
      'municipality': municipality,
      'ward': ward,
      'venue': venue,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'status': status.toDbString(),
      'assigned_staff_ids': assignedStaffIds.join(','),
      'total_patients_registered': totalPatientsRegistered,
      'tenant_id': tenantId,
      'organization_name': organizationName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory CampModel.fromMap(Map<String, dynamic> map) {
    return CampModel(
      id: map['id'] as String,
      campCode: map['camp_code'] as String,
      name: map['name'] as String,
      district: map['district'] as String,
      municipality: map['municipality'] as String? ?? '',
      ward: map['ward'] as String? ?? '',
      venue: map['venue'] as String? ?? '',
      startDate: DateTime.tryParse(map['start_date'] as String? ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(map['end_date'] as String? ?? '') ?? DateTime.now(),
      status: CampStatus.fromString(map['status'] as String? ?? ''),
      assignedStaffIds: map['assigned_staff_ids'] != null && (map['assigned_staff_ids'] as String).isNotEmpty
          ? (map['assigned_staff_ids'] as String).split(',')
          : [],
      totalPatientsRegistered: map['total_patients_registered'] as int? ?? 0,
      tenantId: map['tenant_id'] as String? ?? 'tenant_bir_hospital',
      organizationName: map['organization_name'] as String? ?? 'Bir Hospital Gyno Outreach',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
    );
  }

  CampModel copyWith({
    String? id,
    String? campCode,
    String? name,
    String? district,
    String? municipality,
    String? ward,
    String? venue,
    DateTime? startDate,
    DateTime? endDate,
    CampStatus? status,
    List<String>? assignedStaffIds,
    int? totalPatientsRegistered,
    String? tenantId,
    String? organizationName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CampModel(
      id: id ?? this.id,
      campCode: campCode ?? this.campCode,
      name: name ?? this.name,
      district: district ?? this.district,
      municipality: municipality ?? this.municipality,
      ward: ward ?? this.ward,
      venue: venue ?? this.venue,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      assignedStaffIds: assignedStaffIds ?? this.assignedStaffIds,
      totalPatientsRegistered: totalPatientsRegistered ?? this.totalPatientsRegistered,
      tenantId: tenantId ?? this.tenantId,
      organizationName: organizationName ?? this.organizationName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
