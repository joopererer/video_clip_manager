import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 配置管理服务
/// 用于管理外部 scraper 的配置，如 API Key 等
class ConfigService {
  static const String _configFileName = 'external_scrapers_config.json';
  static Map<String, dynamic>? _config;

  /// 获取配置
  static Future<Map<String, dynamic>> getConfig() async {
    if (_config != null) {
      return _config!;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_configFileName');

      if (await file.exists()) {
        final content = await file.readAsString();
        _config = json.decode(content);
      } else {
        _config = _getDefaultConfig();
        await _saveConfig();
      }
    } catch (e) {
      print('ConfigService: Error loading config: $e');
      _config = _getDefaultConfig();
    }

    return _config!;
  }

  /// 保存配置
  static Future<void> saveConfig(Map<String, dynamic> config) async {
    _config = config;
    await _saveConfig();
  }

  /// 获取特定配置项
  static Future<String?> getConfigValue(String key) async {
    final config = await getConfig();
    return config[key] as String?;
  }

  /// 设置配置项
  static Future<void> setConfigValue(String key, String value) async {
    final config = await getConfig();
    config[key] = value;
    await saveConfig(config);
  }

  /// 检查是否配置了 TMDB API Key
  static Future<bool> isTmdbApiKeyConfigured() async {
    final apiKey = await getConfigValue('tmdb_api_key');
    return apiKey != null && apiKey.isNotEmpty && apiKey != 'YOUR_TMDB_API_KEY';
  }

  /// 获取 TMDB API Key
  static Future<String?> getTmdbApiKey() async {
    final apiKey = await getConfigValue('tmdb_api_key');
    if (apiKey == null || apiKey.isEmpty || apiKey == 'YOUR_TMDB_API_KEY') {
      return null;
    }
    return apiKey;
  }

  /// 设置 TMDB API Key
  static Future<void> setTmdbApiKey(String apiKey) async {
    await setConfigValue('tmdb_api_key', apiKey);
  }

  /// 获取 MissAV Cookie
  static Future<String?> getMissavCookie() async {
    return await getConfigValue('missav_cookie');
  }

  /// 设置 MissAV Cookie
  static Future<void> setMissavCookie(String cookie) async {
    await setConfigValue('missav_cookie', cookie);
  }

  /// 获取 MissAV 代理设置
  static Future<String?> getMissavProxy() async {
    return await getConfigValue('missav_proxy');
  }

  /// 设置 MissAV 代理设置
  static Future<void> setMissavProxy(String proxy) async {
    await setConfigValue('missav_proxy', proxy);
  }

  /// 检查是否配置了 MissAV Cookie
  static Future<bool> isMissavCookieConfigured() async {
    final cookie = await getMissavCookie();
    return cookie != null && cookie.isNotEmpty;
  }

  /// 检查是否配置了 MissAV 代理
  static Future<bool> isMissavProxyConfigured() async {
    final proxy = await getMissavProxy();
    return proxy != null && proxy.isNotEmpty;
  }

  /// 检查外部 scraper 是否可用
  static Future<Map<String, bool>> checkExternalScrapersAvailability() async {
    final scrapers = <String, bool>{};

    // 检查 yt-dlp
    try {
      final result = await Process.run('yt-dlp', ['--version']);
      scrapers['yt-dlp'] = result.exitCode == 0;
    } catch (e) {
      scrapers['yt-dlp'] = false;
    }

    // 检查 javscraper
    try {
      final result = await Process.run('pip', ['show', 'javscraper']);
      scrapers['javscraper'] = result.exitCode == 0;
    } catch (e) {
      scrapers['javscraper'] = false;
    }

    // 检查 Python
    try {
      final result = await Process.run('python', ['--version']);
      scrapers['python'] = result.exitCode == 0;
    } catch (e) {
      scrapers['python'] = false;
    }

    // 检查 TMDB API Key
    scrapers['tmdb_api_key'] = await isTmdbApiKeyConfigured();

    return scrapers;
  }

  /// 获取默认配置
  static Map<String, dynamic> _getDefaultConfig() {
    return {
      'tmdb_api_key': 'YOUR_TMDB_API_KEY',
      'missav_cookie': '',
      'missav_proxy': '',
      'enable_external_scrapers': true,
      'preferred_scrapers': ['yt-dlp', 'jav-scraper', 'tmdb'],
      'request_timeout': 30,
      'max_retries': 3,
      'cache_duration_hours': 24,
    };
  }

  /// 保存配置到文件
  static Future<void> _saveConfig() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_configFileName');
      await file.writeAsString(json.encode(_config));
    } catch (e) {
      print('ConfigService: Error saving config: $e');
    }
  }

  /// 重置配置
  static Future<void> resetConfig() async {
    _config = _getDefaultConfig();
    await _saveConfig();
  }

  /// 导出配置
  static Future<String> exportConfig() async {
    final config = await getConfig();
    return json.encode(config);
  }

  /// 导入配置
  static Future<void> importConfig(String configJson) async {
    try {
      final config = json.decode(configJson) as Map<String, dynamic>;
      await saveConfig(config);
    } catch (e) {
      print('ConfigService: Error importing config: $e');
      throw Exception('Invalid config format');
    }
  }
}
