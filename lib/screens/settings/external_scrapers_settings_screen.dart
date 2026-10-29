import 'package:flutter/material.dart';

import '../../services/config_service.dart';
import '../../services/external_scraper_service.dart';
import '../../theme/app_colors.dart';

class ExternalScrapersSettingsScreen extends StatefulWidget {
  const ExternalScrapersSettingsScreen({super.key});

  @override
  State<ExternalScrapersSettingsScreen> createState() =>
      _ExternalScrapersSettingsScreenState();
}

class _ExternalScrapersSettingsScreenState
    extends State<ExternalScrapersSettingsScreen> {
  final _tmdbApiKeyController = TextEditingController();
  final _missavCookieController = TextEditingController();
  final _missavProxyController = TextEditingController();
  Map<String, bool> _scrapersAvailability = {};
  bool _isLoading = true;
  bool _isInstalling = false;
  bool _obscureTmdb = true;

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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final tmdbApiKey = await ConfigService.getTmdbApiKey();
      _tmdbApiKeyController.text = tmdbApiKey ?? '';

      final missavCookie = await ConfigService.getMissavCookie();
      _missavCookieController.text = missavCookie ?? '';

      final missavProxy = await ConfigService.getMissavProxy();
      _missavProxyController.text = missavProxy ?? '';

      _scrapersAvailability =
          await ExternalScraperService.getAvailableScrapers();
    } catch (e) {
      _toast('加载设置失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveTmdbApiKey() async {
    try {
      await ConfigService.setTmdbApiKey(_tmdbApiKeyController.text);
      _toast('TMDB API Key 已保存');
      await _loadSettings();
    } catch (e) {
      _toast('保存失败: $e');
    }
  }

  Future<void> _saveMissavSettings() async {
    try {
      await ConfigService.setMissavCookie(_missavCookieController.text);
      await ConfigService.setMissavProxy(_missavProxyController.text);
      _toast('MissAV 设置已保存');
    } catch (e) {
      _toast('保存失败: $e');
    }
  }

  Future<void> _installDependencies() async {
    setState(() => _isInstalling = true);
    try {
      final success = await ExternalScraperService.installDependencies();
      if (success) {
        _toast('依赖安装成功');
        await _loadSettings();
      } else {
        _toast('依赖安装失败，请手动安装');
      }
    } catch (e) {
      _toast('安装失败: $e');
    } finally {
      if (mounted) setState(() => _isInstalling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('外部 Scraper 设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadSettings,
            tooltip: '刷新状态',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusCard(c),
                      const SizedBox(height: 16),
                      _buildTmdbCard(c),
                      const SizedBox(height: 16),
                      _buildMissavCard(c),
                      const SizedBox(height: 16),
                      _buildInstallCard(c),
                      const SizedBox(height: 16),
                      _buildHelpCard(c),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ---- 通用分区卡片 ----

  Widget _card({
    required AppColorExtension c,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _statusChip(AppColorExtension c, bool ok) {
    final tone = ok ? c.success : c.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        ok ? '可用' : '不可用',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: tone,
        ),
      ),
    );
  }

  Widget _buildStatusCard(AppColorExtension c) {
    return _card(
      c: c,
      icon: Icons.monitor_heart_outlined,
      title: 'Scraper 状态',
      subtitle: '当前环境下各抓取后端的可用情况',
      children: [
        if (_scrapersAvailability.isEmpty)
          Text('暂无状态信息', style: TextStyle(color: c.textMuted, fontSize: 13)),
        for (final entry in _scrapersAvailability.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  entry.value
                      ? Icons.check_circle_outline
                      : Icons.remove_circle_outline,
                  size: 18,
                  color: entry.value ? c.success : c.warning,
                ),
                const SizedBox(width: 10),
                Text(
                  entry.key,
                  style: TextStyle(color: c.textPrimary, fontSize: 14),
                ),
                const Spacer(),
                _statusChip(c, entry.value),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTmdbCard(AppColorExtension c) {
    return _card(
      c: c,
      icon: Icons.movie_filter_outlined,
      title: 'TMDB API Key',
      subtitle: '用于获取电影和剧集信息。请访问 themoviedb.org/settings/api 申请。',
      children: [
        TextField(
          controller: _tmdbApiKeyController,
          obscureText: _obscureTmdb,
          decoration: InputDecoration(
            labelText: 'TMDB API Key',
            hintText: '输入你的 TMDB API Key',
            isDense: true,
            prefixIcon: const Icon(Icons.key, size: 18),
            suffixIcon: IconButton(
              tooltip: _obscureTmdb ? '显示' : '隐藏',
              icon: Icon(
                _obscureTmdb ? Icons.visibility : Icons.visibility_off,
                size: 18,
              ),
              onPressed: () => setState(() => _obscureTmdb = !_obscureTmdb),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(onPressed: _saveTmdbApiKey, child: const Text('保存')),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _tmdbApiKeyController.clear,
              child: const Text('清除'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMissavCard(AppColorExtension c) {
    return _card(
      c: c,
      icon: Icons.cookie_outlined,
      title: 'MissAV 设置',
      subtitle: '配置 Cookie 和代理以获取更准确的视频标题。Cookie 可从浏览器开发者工具中复制。',
      children: [
        TextField(
          controller: _missavCookieController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'MissAV Cookie',
            hintText: '输入 MissAV Cookie（可选）',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _missavProxyController,
          decoration: const InputDecoration(
            labelText: 'HTTP 代理（可选）',
            hintText: 'http://proxy:port 或 socks5://proxy:port',
            isDense: true,
            prefixIcon: Icon(Icons.vpn_lock_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
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
    );
  }

  Widget _buildInstallCard(AppColorExtension c) {
    return _card(
      c: c,
      icon: Icons.extension_outlined,
      title: '安装依赖',
      subtitle: '自动安装 Python 依赖包，包括 jav-scraper、requests 等。',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: _isInstalling ? null : _installDependencies,
            icon: _isInstalling
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download, size: 18),
            label: Text(_isInstalling ? '正在安装...' : '安装依赖'),
          ),
        ),
      ],
    );
  }

  Widget _buildHelpCard(AppColorExtension c) {
    final bodyStyle = TextStyle(
      fontSize: 13,
      height: 1.6,
      color: c.textSecondary,
    );
    return _card(
      c: c,
      icon: Icons.help_outline,
      title: '使用说明',
      children: [
        Text('• yt-dlp: 通用视频下载器，支持 1000+ 网站', style: bodyStyle),
        Text('• jav-scraper: 专门针对 JAV 内容的信息获取', style: bodyStyle),
        Text('• TMDB API: 电影和剧集信息获取', style: bodyStyle),
        const SizedBox(height: 12),
        Text('如果自动安装失败，请手动运行:', style: bodyStyle),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.borderSubtle),
          ),
          child: SelectableText(
            'pip install jav-scraper requests beautifulsoup4 lxml tmdbv3api yt-dlp',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12.5,
              color: c.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
