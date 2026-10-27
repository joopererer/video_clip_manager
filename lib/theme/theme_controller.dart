import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_palettes.dart';
import 'app_theme.dart';

/// 管理用户选择的配色方案（预设或自定义强调色），并持久化到 SharedPreferences。
class ThemeController extends ChangeNotifier {
  static const String _prefsKeyPalette = 'ui_palette_id';
  static const String _prefsKeyCustomAccent = 'ui_custom_accent';

  final SharedPreferences _prefs;

  late String _paletteId;
  late Color _customAccent;
  late ThemeData _themeData;

  ThemeController(this._prefs) {
    _paletteId = _prefs.getString(_prefsKeyPalette) ?? AppPalette.defaultId;
    final stored = _prefs.getInt(_prefsKeyCustomAccent);
    _customAccent = stored != null
        ? Color(stored)
        : AppPalette.defaultCustomAccent;
    _themeData = _buildTheme();
  }

  String get paletteId => _paletteId;
  Color get customAccent => _customAccent;
  bool get isCustom => _paletteId == AppPalette.customId;
  ThemeData get themeData => _themeData;

  AppColorExtension get colors => _currentPalette().colors;

  AppPalette _currentPalette() =>
      isCustom ? AppPalette.custom(_customAccent) : AppPalette.byId(_paletteId);

  ThemeData _buildTheme() => AppTheme.fromColors(_currentPalette().colors);

  Future<void> selectPreset(String id) async {
    if (_paletteId == id) return;
    _paletteId = id;
    _themeData = _buildTheme();
    notifyListeners();
    await _prefs.setString(_prefsKeyPalette, id);
  }

  Future<void> setCustomAccent(Color accent) async {
    _customAccent = accent;
    _paletteId = AppPalette.customId;
    _themeData = _buildTheme();
    notifyListeners();
    await _prefs.setString(_prefsKeyPalette, AppPalette.customId);
    await _prefs.setInt(_prefsKeyCustomAccent, accent.toARGB32());
  }
}
