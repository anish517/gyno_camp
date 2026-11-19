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

  /// Canonical deduplication/matching key ignoring prefixes ("Nurse"/"Sister"),
  /// NNC suffixes, periods (so "S. Shrestha" and "S Shrestha" merge), extra
  /// whitespace, and letter case.
  static String canonicalKey(String raw) {
    final parsed = parse(raw);
    return _canonicalizeName(parsed.name);
  }

  String get canonicalNameKey => _canonicalizeName(name);

  static String _canonicalizeName(String rawName) {
    return rawName
        .replaceAll('.', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  static NurseProfile pickPreferred(
    NurseProfile existing,
    NurseProfile candidate,
  ) {
    if (!existing.hasRegistration && candidate.hasRegistration) return candidate;
    if (existing.hasRegistration && !candidate.hasRegistration) return existing;

    final existingHasDot = existing.name.contains('.');
    final candidateHasDot = candidate.name.contains('.');
    if (!existingHasDot && candidateHasDot) return candidate;
    if (existingHasDot && !candidateHasDot) return existing;

    final existingMixed = existing.name != existing.name.toLowerCase() &&
        existing.name != existing.name.toUpperCase();
    final candidateMixed = candidate.name != candidate.name.toLowerCase() &&
        candidate.name != candidate.name.toUpperCase();
    if (!existingMixed && candidateMixed) return candidate;
    return existing;
  }

  static bool namesMatch(String a, String b) {
    final nurseA = parse(a);
    final nurseB = parse(b);
    final keyA = nurseA.isValid
        ? nurseA.canonicalNameKey
        : _canonicalizeName(_stripPrefix(a));
    final keyB = nurseB.isValid
        ? nurseB.canonicalNameKey
        : _canonicalizeName(_stripPrefix(b));
    if (keyA.isEmpty || keyB.isEmpty) return false;
    if (keyA == keyB || keyA.contains(keyB) || keyB.contains(keyA)) {
      if (nurseA.hasRegistration && nurseB.hasRegistration) {
        return nurseA.registrationNumber.toLowerCase() ==
            nurseB.registrationNumber.toLowerCase();
      }
      return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is NurseProfile && canonicalNameKey == other.canonicalNameKey;

  @override
  int get hashCode => canonicalNameKey.hashCode;

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
