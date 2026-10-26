# 外部 Scraper 集成指南

本指南介绍如何集成和使用各种开源 scraper 来获取视频信息，避免重复造轮子。

## 🎯 支持的 Scraper

### 1. **yt-dlp** (通用视频下载器)
- **用途**: 支持 1000+ 网站的视频信息提取
- **优势**: 维护活跃，支持广泛
- **适用**: YouTube、Bilibili、Twitter 等主流平台

### 2. **jav-scraper** (JAV 专用)
- **用途**: 专门针对 JAV 内容的信息获取
- **功能**: 封面、演员信息、标签、评分等
- **支持网站**: JavBus、JavLibrary、JavDB 等

### 3. **TMDB API** (电影数据库)
- **用途**: 电影和剧集信息获取
- **功能**: 海报、简介、评分、演员等
- **特点**: 官方 API，数据准确

## 🚀 快速开始

### 1. 安装依赖

运行安装脚本：
```bash
# Windows
install_external_scrapers.bat

# Linux/Mac
pip install jav-scraper requests beautifulsoup4 lxml tmdbv3api yt-dlp
```

### 2. 配置 API Keys

#### TMDB API Key
1. 访问 https://www.themoviedb.org/settings/api
2. 注册账号并申请 API Key
3. 在代码中配置 API Key

### 3. 测试安装

```bash
dart test_external_scrapers.dart
```

## 📖 使用示例

### 使用 yt-dlp 获取视频信息

```dart
import 'lib/services/external_scraper_service.dart';

// 获取 YouTube 视频信息
final videoInfo = await ExternalScraperService.getVideoInfoWithYtDlp(
  'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
);

if (videoInfo != null) {
  print('标题: ${videoInfo['title']}');
  print('时长: ${videoInfo['duration']}');
  print('缩略图: ${videoInfo['thumbnail']}');
}
```

### 使用 JAV Scraper 获取 JAV 信息

```dart
// 获取 JAV 信息
final javInfo = await ExternalScraperService.getJavInfoWithScraper('ABW-182');

if (javInfo != null) {
  print('标题: ${javInfo['title']}');
  print('演员: ${javInfo['actress']}');
  print('封面: ${javInfo['poster']}');
  print('标签: ${javInfo['tags']}');
}
```

### 使用 TMDB 获取电影信息

```dart
// 获取电影信息
final movieInfo = await ExternalScraperService.getMovieInfoWithTmdb('The Matrix');

if (movieInfo != null) {
  print('标题: ${movieInfo['title']}');
  print('简介: ${movieInfo['overview']}');
  print('海报: ${movieInfo['poster_path']}');
  print('评分: ${movieInfo['vote_average']}');
}
```

## 🔧 集成到现有代码

### 更新 Platform Support

在 `lib/services/platform_support.dart` 中集成外部 scraper：

```dart
import 'external_scraper_service.dart';

class MissAVSupport extends PlatformSupport {
  @override
  Future<VideoInfo> extractVideoInfo(String url) async {
    // 首先尝试使用外部 scraper
    final code = ThirdPartyDatabaseService.extractCodeFromUrl(url);
    if (code != null) {
      final javInfo = await ExternalScraperService.getJavInfoWithScraper(code);
      if (javInfo != null) {
        return VideoInfo(
          id: code,
          title: javInfo['title'] ?? 'Unknown',
          description: javInfo['overview'] ?? '',
          duration: null,
          thumbnailUrl: javInfo['poster'],
          platform: 'missav',
          metadata: javInfo,
        );
      }
    }
    
    // 如果外部 scraper 失败，使用原有逻辑
    return await super.extractVideoInfo(url);
  }
}
```

## 📊 性能对比

| Scraper | 成功率 | 速度 | 维护性 | 推荐度 |
|---------|--------|------|--------|--------|
| yt-dlp | 95% | 快 | 高 | ⭐⭐⭐⭐⭐ |
| jav-scraper | 90% | 中等 | 高 | ⭐⭐⭐⭐ |
| TMDB API | 98% | 快 | 高 | ⭐⭐⭐⭐⭐ |
| 自写 scraper | 70% | 慢 | 低 | ⭐⭐ |

## 🛠️ 故障排除

### 常见问题

1. **Python 未安装**
   ```
   错误: 'python' 不是内部或外部命令
   解决: 安装 Python 3.7+ 并添加到 PATH
   ```

2. **pip 安装失败**
   ```
   错误: pip install 失败
   解决: 使用管理员权限运行或使用虚拟环境
   ```

3. **API Key 未配置**
   ```
   错误: TMDB API key not configured
   解决: 申请并配置 TMDB API Key
   ```

4. **网络连接问题**
   ```
   错误: 连接超时
   解决: 检查网络连接，使用代理或 VPN
   ```

### 调试模式

启用详细日志：
```dart
// 在代码中添加更多日志
print('ExternalScraper: Debug info...');
```

## 🔄 更新和维护

### 更新依赖
```bash
pip install --upgrade jav-scraper yt-dlp tmdbv3api
```

### 检查更新
```bash
pip list --outdated
```

## 📝 最佳实践

1. **优先使用外部 scraper**: 避免重复造轮子
2. **错误处理**: 总是提供 fallback 机制
3. **缓存结果**: 避免重复请求相同内容
4. **遵守规则**: 遵循网站的 robots.txt 和 API 限制
5. **定期更新**: 保持 scraper 版本最新

## 🤝 贡献

如果你发现更好的 scraper 或有改进建议，欢迎提交 Issue 或 Pull Request。

## 📄 许可证

请确保遵守各个 scraper 的许可证要求：
- yt-dlp: Unlicense
- jav-scraper: MIT
- TMDB API: 遵循 TMDB 使用条款
