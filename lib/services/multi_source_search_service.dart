import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'external_scraper_service.dart';
import 'third_party_database_service.dart';

/// 多源搜索结果
class MultiSourceResult {
  final String title;
  final String source;
  final String? thumbnailUrl;
  final Map<String, dynamic> metadata;
  final double confidence; // 0.0 - 1.0

  MultiSourceResult({
    required this.title,
    required this.source,
    this.thumbnailUrl,
    required this.metadata,
    this.confidence = 1.0,
  });

  @override
  String toString() {
    return 'MultiSourceResult(title: $title, source: $source, confidence: $confidence)';
  }
}

/// 多源搜索服务
class MultiSourceSearchService {
  static const int _timeoutSeconds = 10;
  
  /// 从多个数据源搜索视频信息
  static Future<List<MultiSourceResult>> searchVideoInfo(String code) async {
    print('MultiSource: Starting multi-source search for code: $code');
    
    final results = <MultiSourceResult>[];
    final futures = <Future<void>>[];
    
    // 1. MissAV 原生页面搜索
    futures.add(_searchMissav(code).then((result) {
      if (result != null) {
        results.add(result);
        print('MultiSource: Added MissAV result: ${result.title}');
      }
    }));
    
    // 2. JavDB 搜索
    futures.add(_searchJavdb(code).then((result) {
      if (result != null) {
        results.add(result);
        print('MultiSource: Added JavDB result: ${result.title}');
      }
    }));
    
    // 3. JavMost 搜索
    futures.add(_searchJavmost(code).then((result) {
      if (result != null) {
        results.add(result);
        print('MultiSource: Added JavMost result: ${result.title}');
      }
    }));
    
    // 4. JavLibrary 搜索
    futures.add(_searchJavlibrary(code).then((result) {
      if (result != null) {
        results.add(result);
        print('MultiSource: Added JavLibrary result: ${result.title}');
      }
    }));
    
    // 等待所有搜索完成
    await Future.wait(futures, eagerError: false);
    
    // 去重和排序
    final uniqueResults = _deduplicateAndSort(results);
    
    print('MultiSource: Found ${uniqueResults.length} unique results');
    for (final result in uniqueResults) {
      print('MultiSource: - ${result.source}: ${result.title} (confidence: ${result.confidence})');
    }
    
    return uniqueResults;
  }
  
  /// 搜索 MissAV 原生页面
  static Future<MultiSourceResult?> _searchMissav(String code) async {
    try {
      // 尝试日文页面
      final jaUrl = 'https://missav.ws/ja/$code-uncensored-leak';
      final result = await ExternalScraperService.getMissavPageContent(jaUrl);
      
      if (result != null && (result['success'] == true || result['success'] == 'true')) {
        final title = result['title'] as String?;
        if (title != null && title.isNotEmpty) {
          return MultiSourceResult(
            title: title,
            source: 'MissAV (Japanese)',
            metadata: {
              'url': jaUrl,
              'content_length': result['content_length'],
            },
            confidence: 0.95, // 原生页面，置信度最高
          );
        }
      }
      
      // 尝试法文页面
      final frUrl = 'https://missav.ws/fr/$code-uncensored-leak';
      final frResult = await ExternalScraperService.getMissavPageContent(frUrl);
      
      if (frResult != null && (frResult['success'] == true || frResult['success'] == 'true')) {
        final title = frResult['title'] as String?;
        if (title != null && title.isNotEmpty) {
          return MultiSourceResult(
            title: title,
            source: 'MissAV (French)',
            metadata: {
              'url': frUrl,
              'content_length': frResult['content_length'],
            },
            confidence: 0.90,
          );
        }
      }
      
      return null;
    } catch (e) {
      print('MultiSource: MissAV search error: $e');
      return null;
    }
  }
  
  /// 搜索 JavDB
  static Future<MultiSourceResult?> _searchJavdb(String code) async {
    try {
      final info = await ThirdPartyDatabaseService.getThumbnailFromDatabase(code);
      if (info != null && info['title'] != null) {
        return MultiSourceResult(
          title: info['title'] as String,
          source: 'JavDB',
          thumbnailUrl: info['thumbnail'] as String?,
          metadata: info,
          confidence: 0.85,
        );
      }
      return null;
    } catch (e) {
      print('MultiSource: JavDB search error: $e');
      return null;
    }
  }
  
  /// 搜索 JavMost
  static Future<MultiSourceResult?> _searchJavmost(String code) async {
    try {
      final info = await ThirdPartyDatabaseService.getThumbnailFromDatabase(code);
      if (info != null && info['title'] != null) {
        return MultiSourceResult(
          title: info['title'] as String,
          source: 'JavMost',
          thumbnailUrl: info['thumbnail'] as String?,
          metadata: info,
          confidence: 0.80,
        );
      }
      return null;
    } catch (e) {
      print('MultiSource: JavMost search error: $e');
      return null;
    }
  }
  
  /// 搜索 JavLibrary
  static Future<MultiSourceResult?> _searchJavlibrary(String code) async {
    try {
      final info = await ThirdPartyDatabaseService.getThumbnailFromDatabase(code);
      if (info != null && info['title'] != null) {
        return MultiSourceResult(
          title: info['title'] as String,
          source: 'JavLibrary',
          thumbnailUrl: info['thumbnail'] as String?,
          metadata: info,
          confidence: 0.75,
        );
      }
      return null;
    } catch (e) {
      print('MultiSource: JavLibrary search error: $e');
      return null;
    }
  }
  
  /// 去重和排序结果
  static List<MultiSourceResult> _deduplicateAndSort(List<MultiSourceResult> results) {
    final uniqueResults = <MultiSourceResult>[];
    final seenTitles = <String>{};
    
    for (final result in results) {
      // 标准化标题进行比较
      final normalizedTitle = _normalizeTitle(result.title);
      
      if (!seenTitles.contains(normalizedTitle)) {
        seenTitles.add(normalizedTitle);
        uniqueResults.add(result);
      } else {
        // 如果标题重复，保留置信度更高的
        final existingIndex = uniqueResults.indexWhere(
          (r) => _normalizeTitle(r.title) == normalizedTitle
        );
        if (existingIndex != -1 && result.confidence > uniqueResults[existingIndex].confidence) {
          uniqueResults[existingIndex] = result;
        }
      }
    }
    
    // 按置信度排序
    uniqueResults.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    return uniqueResults;
  }
  
  /// 标准化标题用于比较
  static String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // 移除标点符号
        .replaceAll(RegExp(r'\s+'), ' ') // 合并多个空格
        .trim();
  }
  
  /// 智能推荐最佳结果
  static MultiSourceResult? getRecommendedResult(List<MultiSourceResult> results) {
    if (results.isEmpty) return null;
    
    // 优先选择 MissAV 原生页面的结果
    final missavResult = results.where((r) => r.source.startsWith('MissAV')).firstOrNull;
    if (missavResult != null) {
      return missavResult;
    }
    
    // 否则选择置信度最高的
    return results.first;
  }
  
  /// 检查结果是否相似
  static bool areResultsSimilar(MultiSourceResult a, MultiSourceResult b) {
    final normalizedA = _normalizeTitle(a.title);
    final normalizedB = _normalizeTitle(b.title);
    
    // 计算相似度（简单的包含关系检查）
    if (normalizedA.contains(normalizedB) || normalizedB.contains(normalizedA)) {
      return true;
    }
    
    // 可以在这里添加更复杂的相似度算法
    return false;
  }
}
