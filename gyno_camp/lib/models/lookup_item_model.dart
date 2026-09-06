class LookupItemModel {
  final String id;
  final String category; // 'diagnosis', 'medicine', 'referral_hospital', 'district', 'ward'
  final String code;
  final String labelEn;
  final String labelNe;
  final bool isActive;
  final int sortOrder;

  const LookupItemModel({
    required this.id,
    required this.category,
    required this.code,
    required this.labelEn,
    required this.labelNe,
    this.isActive = true,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'code': code,
      'label_en': labelEn,
      'label_ne': labelNe,
      'is_active': isActive ? 1 : 0,
      'sort_order': sortOrder,
    };
  }

  factory LookupItemModel.fromMap(Map<String, dynamic> map) {
    return LookupItemModel(
      id: map['id'] as String,
      category: map['category'] as String,
      code: map['code'] as String,
      labelEn: map['label_en'] as String,
      labelNe: map['label_ne'] as String? ?? '',
      isActive: (map['is_active'] is int)
          ? (map['is_active'] as int) == 1
          : (map['is_active'] as bool? ?? true),
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  LookupItemModel copyWith({
    String? id,
    String? category,
    String? code,
    String? labelEn,
    String? labelNe,
    bool? isActive,
    int? sortOrder,
  }) {
    return LookupItemModel(
      id: id ?? this.id,
      category: category ?? this.category,
      code: code ?? this.code,
      labelEn: labelEn ?? this.labelEn,
      labelNe: labelNe ?? this.labelNe,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
