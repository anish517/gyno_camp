class LookupItemModel {
  final String id;
  final String category; // 'diagnosis', 'medicine', 'referral_hospital', 'district', 'ward'
  final String? subCategory; // e.g. 'Pelvic Floor & Incontinence', 'Antibiotics & Antifungals'
  final String code;
  final String labelEn;
  final String labelNe;
  final bool isActive;
  final int sortOrder;
  final String tenantId;
  final bool isDeleted;
  final String? campId; // null or empty means global default; otherwise camp-specific
  final List<String> excludedCampIds; // Camp IDs where this global default item has been excluded/removed

  const LookupItemModel({
    required this.id,
    required this.category,
    this.subCategory,
    required this.code,
    required this.labelEn,
    required this.labelNe,
    this.isActive = true,
    this.sortOrder = 0,
    this.tenantId = 'tenant_default',
    this.isDeleted = false,
    this.campId,
    this.excludedCampIds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'sub_category': subCategory,
      'code': code,
      'label_en': labelEn,
      'label_ne': labelNe,
      'is_active': isActive ? 1 : 0,
      'sort_order': sortOrder,
      'tenant_id': tenantId,
      'is_deleted': isDeleted ? 1 : 0,
      'camp_id': campId,
      'excluded_camp_ids': excludedCampIds.join(','),
    };
  }

  factory LookupItemModel.fromMap(Map<String, dynamic> map) {
    final excludedRaw = map['excluded_camp_ids'] as String?;
    final excludedList = (excludedRaw != null && excludedRaw.isNotEmpty)
        ? excludedRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : const <String>[];

    return LookupItemModel(
      id: map['id'] as String,
      category: map['category'] as String,
      subCategory: map['sub_category'] as String?,
      code: map['code'] as String,
      labelEn: map['label_en'] as String,
      labelNe: map['label_ne'] as String? ?? '',
      isActive: (map['is_active'] is int)
          ? (map['is_active'] as int) == 1
          : (map['is_active'] as bool? ?? true),
      sortOrder: map['sort_order'] as int? ?? 0,
      tenantId: map['tenant_id'] as String? ?? 'tenant_default',
      isDeleted: (map['is_deleted'] is int)
          ? (map['is_deleted'] as int) == 1
          : (map['is_deleted'] as bool? ?? false),
      campId: map['camp_id'] as String?,
      excludedCampIds: excludedList,
    );
  }

  LookupItemModel copyWith({
    String? id,
    String? category,
    String? subCategory,
    String? code,
    String? labelEn,
    String? labelNe,
    bool? isActive,
    int? sortOrder,
    String? tenantId,
    bool? isDeleted,
    String? campId,
    bool clearCampId = false,
    List<String>? excludedCampIds,
  }) {
    return LookupItemModel(
      id: id ?? this.id,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      code: code ?? this.code,
      labelEn: labelEn ?? this.labelEn,
      labelNe: labelNe ?? this.labelNe,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      tenantId: tenantId ?? this.tenantId,
      isDeleted: isDeleted ?? this.isDeleted,
      campId: clearCampId ? null : (campId ?? this.campId),
      excludedCampIds: excludedCampIds ?? this.excludedCampIds,
    );
  }
}

