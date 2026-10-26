import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import '../data/models.dart';
import 'external_scraper_service.dart';
import 'third_party_database_service.dart';

/// 改进的多源搜索服务
class EnhancedMultiSourceService {
  static const int _timeoutSeconds = 10;
  
  /// 从多个数据源搜索视频信息
  static Future<EnhancedMultiSourceResult> searchVideoInfo(String code) async {
    print('EnhancedMultiSource: Starting enhanced search for code: $code');
    
    final aggregatedResult = AggregatedSearchResult(
      code: code,
      titles: [],
      thumbnails: [],
      metadata: {},
    );
    
    // 1. 首先搜索 MissAV 原生页面（最高优先级）
    await _searchMissav(code, aggregatedResult);
    
    // 2. 检查缺失的数据，从第三方数据源补充
    final hasTitle = aggregatedResult.titles.isNotEmpty;
    final hasThumbnail = aggregatedResult.thumbnails.isNotEmpty;
    
    print('EnhancedMultiSource: After MissAV search - titles: $hasTitle, thumbnails: $hasThumbnail');
    
    // 只有在缺失数据时才搜索第三方数据源
    if (!hasTitle || !hasThumbnail) {
      print('EnhancedMultiSource: Searching third-party sources for missing data');
      
      // 并行搜索第三方数据源
      final futures = <Future<void>>[];
      
      if (!hasTitle) {
        futures.add(_searchJavdb(code, aggregatedResult, searchTitle: true, searchThumbnail: !hasThumbnail));
        futures.add(_searchJavmost(code, aggregatedResult, searchTitle: true, searchThumbnail: !hasThumbnail));
        futures.add(_searchJavlibrary(code, aggregatedResult, searchTitle: true, searchThumbnail: !hasThumbnail));
      } else if (!hasThumbnail) {
        // 只搜索封面图
        futures.add(_searchJavdb(code, aggregatedResult, searchTitle: false, searchThumbnail: true));
        futures.add(_searchJavmost(code, aggregatedResult, searchTitle: false, searchThumbnail: true));
        futures.add(_searchJavlibrary(code, aggregatedResult, searchTitle: false, searchThumbnail: true));
      }
      
      if (futures.isNotEmpty) {
        await Future.wait(futures, eagerError: false);
      }
    }
    
    // 去重和排序
    _deduplicateAndSort(aggregatedResult);
    
    print('EnhancedMultiSource: Final result - ${aggregatedResult.titles.length} titles and ${aggregatedResult.thumbnails.length} thumbnails');
    
    return aggregatedResult.toEnhancedResult();
  }
  
  /// 搜索 MissAV 原生页面
  static Future<void> _searchMissav(String code, AggregatedSearchResult result) async {
    try {
      print('EnhancedMultiSource: Searching MissAV for code: $code');
      
      // 尝试日文页面
      final jaUrl = 'https://missav.ws/ja/$code-uncensored-leak';
      final jaResult = await ExternalScraperService.getMissavPageContent(jaUrl);
      
             if (jaResult != null && (jaResult['success'] == true || jaResult['success'] == 'true')) {
         final title = jaResult['title'] as String?;
         if (title != null && title.isNotEmpty) {
           result.titles.add(SearchResultItem(
             value: title,
             source: 'MissAV (Japanese)',
             confidence: 0.95,
             additionalData: {
               'url': jaUrl,
               'content_length': jaResult['content_length'],
             },
           ));
           print('EnhancedMultiSource: Added MissAV Japanese title: $title');
         }
         
         // 添加封面图
         final thumbnail = jaResult['thumbnail'] as String?;
         if (thumbnail != null && thumbnail.isNotEmpty) {
           result.thumbnails.add(SearchResultItem(
             value: thumbnail,
             source: 'MissAV (Japanese)',
             confidence: 0.95,
             additionalData: {
               'url': jaUrl,
               'content_length': jaResult['content_length'],
             },
           ));
           print('EnhancedMultiSource: Added MissAV Japanese thumbnail: $thumbnail');
         }
       }
      
      // 尝试法文页面
      final frUrl = 'https://missav.ws/fr/$code-uncensored-leak';
      final frResult = await ExternalScraperService.getMissavPageContent(frUrl);
      
             if (frResult != null && (frResult['success'] == true || frResult['success'] == 'true')) {
         final title = frResult['title'] as String?;
         if (title != null && title.isNotEmpty) {
           result.titles.add(SearchResultItem(
             value: title,
             source: 'MissAV (French)',
             confidence: 0.90,
             additionalData: {
               'url': frUrl,
               'content_length': frResult['content_length'],
             },
           ));
           print('EnhancedMultiSource: Added MissAV French title: $title');
         }
         
         // 添加封面图
         final thumbnail = frResult['thumbnail'] as String?;
         if (thumbnail != null && thumbnail.isNotEmpty) {
           result.thumbnails.add(SearchResultItem(
             value: thumbnail,
             source: 'MissAV (French)',
             confidence: 0.90,
             additionalData: {
               'url': frUrl,
               'content_length': frResult['content_length'],
             },
           ));
           print('EnhancedMultiSource: Added MissAV French thumbnail: $thumbnail');
         }
       }
      
    } catch (e) {
      print('EnhancedMultiSource: MissAV search error: $e');
    }
  }
  
  /// 搜索 JavDB
  static Future<void> _searchJavdb(String code, AggregatedSearchResult result, {bool searchTitle = true, bool searchThumbnail = true}) async {
    try {
      print('EnhancedMultiSource: Searching JavDB for code: $code (title: $searchTitle, thumbnail: $searchThumbnail)');
      final info = await ThirdPartyDatabaseService.getThumbnailFromDatabase(code);
      
      if (info != null) {
        // 添加标题（如果需要）
        if (searchTitle) {
          final title = info['title'] as String?;
          if (title != null && title.isNotEmpty && title != 'Unknown Title') {
            result.titles.add(SearchResultItem(
              value: title,
              source: 'JavDB',
              confidence: 0.85,
              additionalData: info,
            ));
            print('EnhancedMultiSource: Added JavDB title: $title');
          }
        }
        
        // 添加封面图（如果需要）
        if (searchThumbnail) {
          final thumbnail = info['thumbnail'] as String?;
          if (thumbnail != null && thumbnail.isNotEmpty) {
            result.thumbnails.add(SearchResultItem(
              value: thumbnail,
              source: 'JavDB',
              confidence: 0.85,
              additionalData: info,
            ));
            print('EnhancedMultiSource: Added JavDB thumbnail: $thumbnail');
          }
        }
      }
      
    } catch (e) {
      print('EnhancedMultiSource: JavDB search error: $e');
    }
  }
  
  /// 搜索 JavMost
  static Future<void> _searchJavmost(String code, AggregatedSearchResult result, {bool searchTitle = true, bool searchThumbnail = true}) async {
    try {
      print('EnhancedMultiSource: Searching JavMost for code: $code (title: $searchTitle, thumbnail: $searchThumbnail)');
      final info = await ThirdPartyDatabaseService.getThumbnailFromDatabase(code);
      
      if (info != null) {
        // 添加标题（如果需要）
        if (searchTitle) {
          final title = info['title'] as String?;
          if (title != null && title.isNotEmpty && title != 'Unknown Title') {
            result.titles.add(SearchResultItem(
              value: title,
              source: 'JavMost',
              confidence: 0.80,
              additionalData: info,
            ));
            print('EnhancedMultiSource: Added JavMost title: $title');
          }
        }
        
        // 添加封面图（如果需要）
        if (searchThumbnail) {
          final thumbnail = info['thumbnail'] as String?;
          if (thumbnail != null && thumbnail.isNotEmpty) {
            result.thumbnails.add(SearchResultItem(
              value: thumbnail,
              source: 'JavMost',
              confidence: 0.80,
              additionalData: info,
            ));
            print('EnhancedMultiSource: Added JavMost thumbnail: $thumbnail');
          }
        }
      }
      
    } catch (e) {
      print('EnhancedMultiSource: JavMost search error: $e');
    }
  }
  
  /// 搜索 JavLibrary
  static Future<void> _searchJavlibrary(String code, AggregatedSearchResult result, {bool searchTitle = true, bool searchThumbnail = true}) async {
    try {
      print('EnhancedMultiSource: Searching JavLibrary for code: $code (title: $searchTitle, thumbnail: $searchThumbnail)');
      final info = await ThirdPartyDatabaseService.getThumbnailFromDatabase(code);
      
      if (info != null) {
        // 添加标题（如果需要）
        if (searchTitle) {
          final title = info['title'] as String?;
          if (title != null && title.isNotEmpty && title != 'Unknown Title') {
            result.titles.add(SearchResultItem(
              value: title,
              source: 'JavLibrary',
              confidence: 0.75,
              additionalData: info,
            ));
            print('EnhancedMultiSource: Added JavLibrary title: $title');
          }
        }
        
        // 添加封面图（如果需要）
        if (searchThumbnail) {
          final thumbnail = info['thumbnail'] as String?;
          if (thumbnail != null && thumbnail.isNotEmpty) {
            result.thumbnails.add(SearchResultItem(
              value: thumbnail,
              source: 'JavLibrary',
              confidence: 0.75,
              additionalData: info,
            ));
            print('EnhancedMultiSource: Added JavLibrary thumbnail: $thumbnail');
          }
        }
      }
      
    } catch (e) {
      print('EnhancedMultiSource: JavLibrary search error: $e');
    }
  }
  
  /// 去重和排序
  static void _deduplicateAndSort(AggregatedSearchResult result) {
    // 去重标题
    final uniqueTitles = <String, SearchResultItem>{};
    for (final title in result.titles) {
      final normalizedTitle = _normalizeTitle(title.value);
      if (!uniqueTitles.containsKey(normalizedTitle) || 
          title.confidence > uniqueTitles[normalizedTitle]!.confidence) {
        uniqueTitles[normalizedTitle] = title;
      }
    }
    result.titles.clear();
    result.titles.addAll(uniqueTitles.values);
    
    // 去重封面图
    final uniqueThumbnails = <String, SearchResultItem>{};
    for (final thumbnail in result.thumbnails) {
      if (!uniqueThumbnails.containsKey(thumbnail.value) || 
          thumbnail.confidence > uniqueThumbnails[thumbnail.value]!.confidence) {
        uniqueThumbnails[thumbnail.value] = thumbnail;
      }
    }
    result.thumbnails.clear();
    result.thumbnails.addAll(uniqueThumbnails.values);
    
    // 按置信度排序
    result.titles.sort((a, b) => b.confidence.compareTo(a.confidence));
    result.thumbnails.sort((a, b) => b.confidence.compareTo(a.confidence));
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
  static EnhancedMultiSourceResult? getRecommendedResult(EnhancedMultiSourceResult result) {
    // 如果只有一个结果，直接返回
    if (!result.hasMultipleChoices) {
      return result;
    }
    
    // 如果有多个选择，返回最佳组合
    return result;
  }
}
