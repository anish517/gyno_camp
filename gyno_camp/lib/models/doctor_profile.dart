/// Represents a medical doctor with their dynamic Nepal Medical Council (NMC) registration number.
///
/// Each doctor has their own unique NMC number that is stored alongside their name.
/// Serialized as: "Dr. Sita Sharma (NMC: 14256)" in the database.
class DoctorProfile {
  final String name; // Cleaned display name without "Dr." prefix
  final String nmcNumber; // Dynamic unique NMC council number for this specific doctor

  const DoctorProfile({required this.name, this.nmcNumber = ''});

  /// Full formatted name including "Dr." prefix
  String get displayName {
    final clean = _stripDrPrefix(name);
    if (clean.isEmpty) return '';
    return 'Dr. $clean';
  }

  /// Strip Dr. prefix from a raw string
  static String stripDrPrefix(String raw) => _stripDrPrefix(raw);

  /// Formatted label for UI chips and PDF headers
  String get formattedLabel =>
      nmcNumber.isNotEmpty ? '$displayName (NMC: $nmcNumber)' : displayName;

  /// Short display for chips (no parenthetical NMC in very compact contexts)
  String get shortLabel => displayName;

  bool get hasNmc => nmcNumber.isNotEmpty;

  bool get isValid => name.trim().isNotEmpty;

  /// Parse a stored doctor string back into a DoctorProfile.
  /// Handles formats like:
  ///   "Dr. Sita Sharma (NMC: 14256)"
  ///   "Sita Sharma [NMC: 14256]"
  ///   "Sita Sharma NMC 14256"
  ///   "Dr. Sita Sharma" (no NMC)
  ///   "Sita Sharma" (plain name)
  static DoctorProfile parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const DoctorProfile(name: '');

    // Try structured NMC patterns: "... (NMC: 14256)" or "... [NMC 2222/3333]"
    final match = RegExp(
      r'^(.*?)\s*[\(\[]\s*NMC[:\s#]*\s*([\w\/-]+)\s*[\)\]]?\s*$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (match != null && match.group(1) != null && match.group(2) != null) {
      final rawName = match.group(1)!.trim();
      final nmc = match.group(2)!.trim();
      final cleanName = _stripDrPrefix(rawName);
      return DoctorProfile(name: cleanName, nmcNumber: nmc);
    }

    // Try inline NMC without brackets: "Sita Sharma NMC 14256" or "Ramesh Karki - NMC 9988"
    final inlineMatch = RegExp(
      r'^(.*?)\s*[-–—:]*\s*NMC[:\s#]*\s*([\w\/-]+)\s*$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (inlineMatch != null &&
        inlineMatch.group(1) != null &&
        inlineMatch.group(2) != null) {
      final rawName = inlineMatch.group(1)!.trim();
      final nmc = inlineMatch.group(2)!.trim();
      final cleanName = _stripDrPrefix(rawName);
      return DoctorProfile(name: cleanName, nmcNumber: nmc);
    }

    // Try parenthesized numeric ID pattern: "... (12345)" or "... [12345]"
    final numMatch = RegExp(
      r'^(.*?)\s*[\(\[]\s*(\d+)\s*[\)\]]?\s*$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (numMatch != null &&
        numMatch.group(1) != null &&
        numMatch.group(2) != null) {
      final rawName = numMatch.group(1)!.trim();
      final nmc = numMatch.group(2)!.trim();
      final cleanName = _stripDrPrefix(rawName);
      if (cleanName.isNotEmpty) {
        return DoctorProfile(name: cleanName, nmcNumber: nmc);
      }
    }

    // Plain name (no NMC)
    return DoctorProfile(name: _stripDrPrefix(trimmed));
  }

  /// Converts to a storage string suitable for saving in doctor_names column.
  String toStorageString() =>
      nmcNumber.isNotEmpty ? '$displayName (NMC: $nmcNumber)' : displayName;

  static String _stripDrPrefix(String raw) {
    return raw
        .trim()
        .replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\s\-–—:]+$'), '')
        .trim();
  }

  /// Canonical deduplication/matching key that ignores "Dr." prefix, "(NMC: ...)"
  /// suffix, periods/dots (so "A. Sharma", "A.Sharma", and "A Sharma" match),
  /// extra whitespace, and letter case.
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

  /// Returns the preferred display variant when merging two entries for the same
  /// doctor (e.g., prefers an entry with an NMC number, then punctuated initials
  /// like "A. Sharma" over "A Sharma", then mixed-case over all-lower/all-upper).
  static DoctorProfile pickPreferred(
    DoctorProfile existing,
    DoctorProfile candidate,
  ) {
    if (!existing.hasNmc && candidate.hasNmc) return candidate;
    if (existing.hasNmc && !candidate.hasNmc) return existing;

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

  /// Canonical doctor name comparison used across filters, reports, and rosters.
  /// Matches punctuation/spacing variants ("Dr. A Sharma" == "Dr. A. Sharma")
  /// while respecting distinct NMC numbers when both sides carry one.
  static bool namesMatch(String a, String b) {
    final docA = parse(a);
    final docB = parse(b);
    final keyA = docA.isValid
        ? docA.canonicalNameKey
        : _canonicalizeName(_stripDrPrefix(a));
    final keyB = docB.isValid
        ? docB.canonicalNameKey
        : _canonicalizeName(_stripDrPrefix(b));
    if (keyA.isEmpty || keyB.isEmpty) return false;
    if (keyA == keyB || keyA.contains(keyB) || keyB.contains(keyA)) {
      if (docA.hasNmc && docB.hasNmc) {
        return docA.nmcNumber.toLowerCase() == docB.nmcNumber.toLowerCase();
      }
      return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is DoctorProfile && canonicalNameKey == other.canonicalNameKey;

  @override
  int get hashCode => canonicalNameKey.hashCode;

  @override
  String toString() => formattedLabel;

  /// Parse a comma-separated doctor_names string into a list of DoctorProfiles.
  static List<DoctorProfile> parseList(String raw) {
    if (raw.trim().isEmpty) return [];
    // Split on commas, but be careful not to split inside "(NMC: xxx)" parentheses
    final parts = _splitDoctorList(raw);
    return parts.map(parse).where((d) => d.isValid).toList();
  }

  /// Serialize a list of DoctorProfiles to a storage string.
  static String serializeList(List<DoctorProfile> profiles) {
    return profiles.map((d) => d.toStorageString()).join(',');
  }

  static List<String> _splitDoctorList(String raw) {
    // Split on commas that are NOT inside parentheses
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
