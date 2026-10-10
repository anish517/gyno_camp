/// Represents a nurse assigned to a camp with an optional Nepal Nursing Council
/// (NNC) registration number.
///
/// This is a camp-level roster entry (free text, like [DoctorProfile]) and is NOT
/// linked to a login account / `UserModel`.
/// Serialized as: "Sita Sharma (NNC: 14256)" in the database.
class NurseProfile {
  final String name; // Cleaned display name without "Nurse"/"Sister" prefix
  final String registrationNumber; // Optional NNC registration number

  const NurseProfile({required this.name, this.registrationNumber = ''});

  /// Display name (prefix such as "Nurse"/"Sister" is stripped for consistency).
  String get displayName => name.trim();

  /// Formatted label for UI chips and PDF headers.
  String get formattedLabel => registrationNumber.isNotEmpty
      ? '$displayName (NNC: $registrationNumber)'
      : displayName;

  /// Short display for chips (no parenthetical registration number).
  String get shortLabel => displayName;

  bool get hasRegistration => registrationNumber.isNotEmpty;

  bool get isValid => name.trim().isNotEmpty;

  static final RegExp _regLabel = RegExp(
    r'(?:NNC|Reg(?:istration)?\.?(?:\s*No\.?)?)',
    caseSensitive: false,
  );

  /// Parse a stored nurse string back into a NurseProfile.
  /// Handles formats like:
  ///   "Sita Sharma (NNC: 14256)"
  ///   "Sita Sharma [Reg: 14256]"
  ///   "Sita Sharma NNC 14256"
  ///   "Nurse Sita Sharma" / "Sister Sita Sharma" (prefix stripped)
  ///   "Sita Sharma" (plain name)
  static NurseProfile parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const NurseProfile(name: '');

    // Structured pattern: "... (NNC: 14256)" or "... [Reg 14256]"
    final match = RegExp(
      '^(.*?)\\s*[\\(\\[]\\s*${_regLabel.pattern}[:\\s#]*\\s*(\\w+)\\s*[\\)\\]]?\\s*\$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (match != null && match.group(1) != null && match.group(2) != null) {
      return NurseProfile(
        name: _stripPrefix(match.group(1)!),
        registrationNumber: match.group(2)!.trim(),
      );
    }

    // Inline pattern without brackets: "Sita Sharma NNC 14256"
    final inlineMatch = RegExp(
      '^(.*?)\\s*[-–—:]*\\s*${_regLabel.pattern}[:\\s#]*\\s*(\\w+)\\s*\$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (inlineMatch != null &&
        inlineMatch.group(1) != null &&
        inlineMatch.group(2) != null) {
      return NurseProfile(
        name: _stripPrefix(inlineMatch.group(1)!),
        registrationNumber: inlineMatch.group(2)!.trim(),
      );
    }

    return NurseProfile(name: _stripPrefix(trimmed));
  }

  /// Converts to a storage string suitable for saving in the nurse_names column.
  String toStorageString() => formattedLabel;

  /// Strips prefixes such as "Staff Nurse", "Nurse", "Sister", etc.
  static String stripPrefixes(String raw) => _stripPrefix(raw);

  static String _stripPrefix(String raw) {
    return raw
        .trim()
        .replaceAll(
          RegExp(r'^((staff\s+nurse|nurse|sister|sr|nsr)\.?\s+)+',
              caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[\s\-–—:]+$'), '')
        .trim();
  }

  @override
  bool operator ==(Object other) =>
      other is NurseProfile &&
      name.toLowerCase().trim() == other.name.toLowerCase().trim();

  @override
  int get hashCode => name.toLowerCase().trim().hashCode;

  @override
  String toString() => formattedLabel;

  /// Parse a comma-separated nurse_names string into a list of NurseProfiles.
  static List<NurseProfile> parseList(String raw) {
    if (raw.trim().isEmpty) return [];
    return splitList(raw).map(parse).where((n) => n.isValid).toList();
  }

  /// Serialize a list of NurseProfiles to a storage string.
  static String serializeList(List<NurseProfile> profiles) {
    return profiles.map((n) => n.toStorageString()).join(',');
  }

  /// Splits a comma-separated nurse list while respecting parentheses/brackets
  /// (so "Sita (NNC: 1), Gita" splits correctly).
  static List<String> splitList(String raw) {
    final result = <String>[];
    int depth = 0;
    final buffer = StringBuffer();
    for (final char in raw.split('')) {
      if (char == '(' || char == '[') {
        depth++;
        buffer.write(char);
      } else if (char == ')' || char == ']') {
        depth--;
        buffer.write(char);
      } else if (char == ',' && depth == 0) {
        final part = buffer.toString().trim();
        if (part.isNotEmpty) result.add(part);
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    final last = buffer.toString().trim();
    if (last.isNotEmpty) result.add(last);
    return result;
  }
}
