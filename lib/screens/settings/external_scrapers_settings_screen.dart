import 'package:flutter/material.dart';
import '../../services/config_service.dart';
import '../../services/external_scraper_service.dart';

class ExternalScrapersSettingsScreen extends StatefulWidget {
  const ExternalScrapersSettingsScreen({super.key});

  @override
  State<ExternalScrapersSettingsScreen> createState() => _ExternalScrapersSettingsScreenState();
}

class _ExternalScrapersSettingsScreenState extends State<ExternalScrapersSettingsScreen> {
  final _tmdbApiKeyController = TextEditingController();
  final _missavCookieController = TextEditingController();
  final _missavProxyController = TextEditingController();
  Map<String, bool> _scrapersAvailability = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _tmdbApiKeyController.dispose();
    _missavCookieController.dispose();
    _missavProxyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 加载 TMDB API Key
      final tmdbApiKey = await ConfigService.getTmdbApiKey();
      _tmdbApiKeyController.text = tmdbApiKey ?? '';

      // 加载 MissAV 设置
      final missavCookie = await ConfigService.getMissavCookie();
      _missavCookieController.text = missavCookie ?? '';
      
      final missavProxy = await ConfigService.getMissavProxy();
      _missavProxyController.text = missavProxy ?? '';

      // 检查 scraper 可用性
      _scrapersAvailability = await ExternalScraperService.getAvailableScrapers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载设置失败: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveTmdbApiKey() async {
    try {
      await ConfigService.setTmdbApiKey(_tmdbApiKeyController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TMDB API Key 已保存')),
      );
      
      // 重新检查可用性
      await _loadSettings();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  Future<void> _saveMissavSettings() async {
    try {
      await ConfigService.setMissavCookie(_missavCookieController.text);
      await ConfigService.setMissavProxy(_missavProxyController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MissAV 设置已保存')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  Future<void> _installDependencies() async {
    try {
      final success = await ExternalScraperService.installDependencies();
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('依赖安装成功')),
        );
        await _loadSettings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('依赖安装失败，请手动安装')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('安装失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('外部 Scraper 设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSettings,
            tooltip: '刷新状态',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 状态概览
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Scraper 状态',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._scrapersAvailability.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    entry.value ? Icons.check_circle : Icons.error,
                                    color: entry.value ? Colors.green : Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(entry.key),
                                  const Spacer(),
                                  Text(
                                    entry.value ? '可用' : '不可用',
                                    style: TextStyle(
                                      color: entry.value ? Colors.green : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // TMDB API Key 设置
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TMDB API Key',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '用于获取电影和剧集信息。请访问 https://www.themoviedb.org/settings/api 申请 API Key。',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _tmdbApiKeyController,
                            decoration: const InputDecoration(
                              labelText: 'TMDB API Key',
                              border: OutlineInputBorder(),
                              hintText: '输入你的 TMDB API Key',
                            ),
                            obscureText: true,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _saveTmdbApiKey,
                                child: const Text('保存'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () {
                                  _tmdbApiKeyController.clear();
                                },
                                child: const Text('清除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // MissAV 设置
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MissAV 设置',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '配置 Cookie 和代理以获取更准确的视频标题。Cookie 可从浏览器开发者工具中复制。',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _missavCookieController,
                            decoration: const InputDecoration(
                              labelText: 'MissAV Cookie',
                              border: OutlineInputBorder(),
                              hintText: '输入 MissAV Cookie（可选）',
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _missavProxyController,
                            decoration: const InputDecoration(
                              labelText: 'HTTP 代理（可选）',
                              border: OutlineInputBorder(),
                              hintText: 'http://proxy:port 或 socks5://proxy:port',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: _saveMissavSettings,
                                child: const Text('保存'),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () {
                                  _missavCookieController.clear();
                                  _missavProxyController.clear();
                                },
                                child: const Text('清除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 安装依赖
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '安装依赖',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '自动安装 Python 依赖包，包括 jav-scraper、requests 等。',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _installDependencies,
                            icon: const Icon(Icons.download),
                            label: const Text('安装依赖'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 使用说明
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '使用说明',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '• yt-dlp: 通用视频下载器，支持 1000+ 网站\n'
                            '• jav-scraper: 专门针对 JAV 内容的信息获取\n'
                            '• TMDB API: 电影和剧集信息获取\n\n'
                            '如果自动安装失败，请手动运行:\n'
                            'pip install jav-scraper requests beautifulsoup4 lxml tmdbv3api yt-dlp',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
