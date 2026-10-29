/// Minimal SemVer parsing/comparison used by the update checker.
///
/// Only what the checker needs: `major.minor.patch` with an optional
/// `-prerelease` and `+build` suffix, tolerant of a leading `v`/`V` and of
/// short tags like `1.2`. Pre-release versions are recognised so they can be
/// excluded from the "is this an update" decision.
class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;
  final String prerelease;

  const SemanticVersion(
    this.major, [
    this.minor = 0,
    this.patch = 0,
    this.prerelease = '',
  ]);

  bool get isPrerelease => prerelease.isNotEmpty;

  static final RegExp _pattern = RegExp(
    r'^[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.\-]+))?(?:\+[0-9A-Za-z.\-]+)?$',
  );

  static SemanticVersion? tryParse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
      match.group(4) ?? '',
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // A stable release is always newer than a pre-release of the same version.
    if (isPrerelease && !other.isPrerelease) return -1;
    if (!isPrerelease && other.isPrerelease) return 1;
    return prerelease.compareTo(other.prerelease);
  }

  bool isNewerThan(SemanticVersion other) => compareTo(other) > 0;

  @override
  String toString() =>
      '$major.$minor.$patch${isPrerelease ? '-$prerelease' : ''}';
}
