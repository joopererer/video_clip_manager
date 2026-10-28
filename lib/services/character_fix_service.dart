/// 字符修复服务
/// 用于修复网页抓取中常见的字符显示问题
class CharacterFixService {
  /// 常见的字符显示问题映射
  static const Map<String, String> _charMappings = {
    // 法语字符
    '茅': 'é', // U+8305 -> U+00E9 (é)
    '莽': 'ç', // U+83BD -> U+00E7 (ç)
    '脙': 'É', // U+8119 -> U+00C9 (É)
    '脗': 'Ç', // U+8117 -> U+00C7 (Ç)
    // 其他可能的字符问题
    '脙漏': 'é', // 组合字符
  };

  /// 修复文本中的字符显示问题
  static String fixCharacters(String text) {
    if (text.isEmpty) return text;

    String fixedText = text;

    // 应用字符映射
    for (final entry in _charMappings.entries) {
      if (fixedText.contains(entry.key)) {
        fixedText = fixedText.replaceAll(entry.key, entry.value);
      }
    }

    // 基于 Unicode 码点的额外修复
    fixedText = _fixByUnicodeCodePoint(fixedText);

    return fixedText;
  }

  /// 基于 Unicode 码点修复字符
  static String _fixByUnicodeCodePoint(String text) {
    String fixedText = text;

    // 检查每个字符的 Unicode 码点
    for (int i = 0; i < fixedText.length; i++) {
      final char = fixedText[i];
      final codePoint = char.codeUnitAt(0);

      // 如果字符的 Unicode 码点是 0xE9，但显示为其他字符，强制替换为 é
      if (codePoint == 0xE9 && char != 'é') {
        fixedText = fixedText.replaceRange(i, i + 1, 'é');
      }

      // 如果字符的 Unicode 码点是 0xE7，但显示为其他字符，强制替换为 ç
      if (codePoint == 0xE7 && char != 'ç') {
        fixedText = fixedText.replaceRange(i, i + 1, 'ç');
      }

      // 如果字符的 Unicode 码点是 0xC9，但显示为其他字符，强制替换为 É
      if (codePoint == 0xC9 && char != 'É') {
        fixedText = fixedText.replaceRange(i, i + 1, 'É');
      }

      // 如果字符的 Unicode 码点是 0xC7，但显示为其他字符，强制替换为 Ç
      if (codePoint == 0xC7 && char != 'Ç') {
        fixedText = fixedText.replaceRange(i, i + 1, 'Ç');
      }
    }

    return fixedText;
  }

  /// 检查文本是否包含需要修复的字符
  static bool needsFixing(String text) {
    if (text.isEmpty) return false;

    // 检查是否包含已知的问题字符
    for (final wrongChar in _charMappings.keys) {
      if (text.contains(wrongChar)) {
        return true;
      }
    }

    // 检查 Unicode 码点问题
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final codePoint = char.codeUnitAt(0);

      // 检查常见的 Unicode 码点问题
      if ((codePoint == 0xE9 && char != 'é') ||
          (codePoint == 0xE7 && char != 'ç') ||
          (codePoint == 0xC9 && char != 'É') ||
          (codePoint == 0xC7 && char != 'Ç')) {
        return true;
      }
    }

    return false;
  }

  /// 获取修复统计信息
  static Map<String, int> getFixStatistics(
    String originalText,
    String fixedText,
  ) {
    final stats = <String, int>{};

    for (final entry in _charMappings.entries) {
      final originalCount = originalText.split(entry.key).length - 1;
      if (originalCount > 0) {
        stats[entry.key] = originalCount;
      }
    }

    return stats;
  }
}
