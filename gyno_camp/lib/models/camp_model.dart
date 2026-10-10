import '../core/constants/app_constants.dart';
import 'doctor_profile.dart';
import 'nurse_profile.dart';

export 'doctor_profile.dart';
export 'nurse_profile.dart';

/// Splits a comma-separated doctor list while respecting parentheses
/// (so "Dr. Anita Sharma (NMC: 12345), Dr. Ram Karki" splits correctly).
List<String> _splitDoctorListRaw(String raw) {
  final result = <String>[];
  int depth = 0;
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch == '(') {
      depth++;
      buffer.write(ch);
    } else if (ch == ')') {
      depth--;
      buffer.write(ch);
    } else if (ch == ',' && depth == 0) {
      result.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  if (buffer.isNotEmpty) result.add(buffer.toString());
  return result;
}

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

  /// A camp is locked (read-only) once it is closed or archived.
  bool get isLocked => this == CampStatus.closed || this == CampStatus.archived;
}

class CampModel {
  final String id;
  final String campCode; // e.g., 'KTM01', 'DHN02'
  final String name;
  final String province; // Nepal Province (Koshi, Madhesh, Bagmati, Gandaki, Lumbini, Karnali, Sudurpashchim)
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
  final String doctorName; // Legacy scalar (kept for backward compat)
  final List<String> doctorNames; // Multi-doctor list (preferred, may include NMC in format "Dr. X (NMC: 12345)")
  final bool showDoctorOnForms; // Camp setting: whether to pre-print doctor name & NMC on generated forms
  final List<String> nurseNames; // Camp nurse roster (free-text, may include NNC in format "Sita (NNC: 12345)"); not login-based
  final bool showNurseOnForms; // Camp setting: whether to pre-print nurse name(s) & NNC on generated forms
  final DateTime createdAt;
  final DateTime? updatedAt;

  const CampModel({
    required this.id,
    required this.campCode,
    required this.name,
    this.province = 'Bagmati',
    required this.district,
    required this.municipality,
    required this.ward,
    required this.venue,
    required this.startDate,
    required this.endDate,
    this.status = CampStatus.draft,
    this.assignedStaffIds = const [],
    this.totalPatientsRegistered = 0,
    this.tenantId = 'tenant_default',
    this.organizationName = 'Community Health Outreach Mission',
    this.doctorName = '',
    this.doctorNames = const [],
    this.showDoctorOnForms = true,
    this.nurseNames = const [],
    this.showNurseOnForms = true,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isOpen => status == CampStatus.open;
  bool isStaffAssigned(String userId) => assignedStaffIds.contains(userId);

  /// Parsed list of DoctorProfiles from the doctorNames list.
  List<DoctorProfile> get doctorProfiles =>
      doctorNames.map(DoctorProfile.parse).where((d) => d.isValid).toList();

  /// Whether the camp has any assigned doctors.
  bool get hasDoctors => doctorNames.isNotEmpty || doctorName.isNotEmpty;

  /// Parsed list of NurseProfiles from the nurseNames list.
  List<NurseProfile> get nurseProfiles =>
      nurseNames.map(NurseProfile.parse).where((n) => n.isValid).toList();

  /// Whether the camp has any assigned nurses.
  bool get hasNurses => nurseNames.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'camp_code': campCode,
      'name': name,
      'province': province,
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
      'doctor_name': doctorName,
      'doctor_names': doctorNames.join(','),
      'show_doctor_on_forms': showDoctorOnForms ? 1 : 0,
      'nurse_names': nurseNames.join(','),
      'show_nurse_on_forms': showNurseOnForms ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory CampModel.fromMap(Map<String, dynamic> map) {
    return CampModel(
      id: map['id'] as String,
      campCode: map['camp_code'] as String,
      name: map['name'] as String,
      province: map['province'] as String? ?? 'Bagmati',
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
      tenantId: map['tenant_id'] as String? ?? 'tenant_default',
      organizationName: map['organization_name'] as String? ?? 'Community Health Outreach Mission',
      doctorName: map['doctor_name'] as String? ?? '',
      doctorNames: () {
        // Try new comma-separated list first (may include NMC info), fall back to legacy scalar
        final raw = map['doctor_names'] as String?;
        if (raw != null && raw.trim().isNotEmpty) {
          // Use parenthesis-aware splitting to avoid splitting within "Name (NMC: 12345)"
          return _splitDoctorListRaw(raw)
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        final legacy = map['doctor_name'] as String? ?? '';
        return legacy.trim().isNotEmpty ? [legacy.trim()] : <String>[];
      }(),
      showDoctorOnForms: () {
        final raw = map['show_doctor_on_forms'];
        if (raw == null) return true; // Default ON for backward compat
        if (raw is bool) return raw;
        if (raw is int) return raw != 0;
        return true;
      }(),
      nurseNames: () {
        final raw = map['nurse_names'] as String?;
        if (raw == null || raw.trim().isEmpty) return <String>[];
        // Parenthesis-aware splitting to avoid splitting within "Name (NNC: 12345)"
        return NurseProfile.splitList(raw)
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }(),
      showNurseOnForms: () {
        final raw = map['show_nurse_on_forms'];
        if (raw == null) return true; // Default ON for backward compat
        if (raw is bool) return raw;
        if (raw is int) return raw != 0;
        return true;
      }(),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
    );
  }

  CampModel copyWith({
    String? id,
    String? campCode,
    String? name,
    String? province,
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
    String? doctorName,
    List<String>? doctorNames,
    bool? showDoctorOnForms,
    List<String>? nurseNames,
    bool? showNurseOnForms,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CampModel(
      id: id ?? this.id,
      campCode: campCode ?? this.campCode,
      name: name ?? this.name,
      province: province ?? this.province,
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
      doctorName: doctorName ?? this.doctorName,
      doctorNames: doctorNames ?? this.doctorNames,
      showDoctorOnForms: showDoctorOnForms ?? this.showDoctorOnForms,
      nurseNames: nurseNames ?? this.nurseNames,
      showNurseOnForms: showNurseOnForms ?? this.showNurseOnForms,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
