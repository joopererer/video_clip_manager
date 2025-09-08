import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/models.dart';
import '../services/hybrid_video_sniffer_service.dart';
import '../services/yt_dlp_service.dart';
import '../services/character_fix_service.dart';

enum UrlValidationStatus {
  none,      // 未验证
  validating, // 验证中
  valid,     // 有效
  invalid,   // 无效
}

class AddOnlineVideoScreen extends StatefulWidget {
  @override
  _AddOnlineVideoScreenState createState() => _AddOnlineVideoScreenState();
}

class _AddOnlineVideoScreenState extends State<AddOnlineVideoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _videoUrlController = TextEditingController();
  final _pageUrlController = TextEditingController();
  final _titleController = TextEditingController();
  
  bool _isLoading = false;
  bool _usePageSniffing = false;
  String? _detectedTitle;
  String? _detectedVideoUrl;
  String? _detectedThumbnail;
  Map<String, String>? _detectedHeaders;
  String? _errorMessage;
  UrlValidationStatus _urlValidationStatus = UrlValidationStatus.none;
  
  @override
  void dispose() {
    _videoUrlController.dispose();
    _pageUrlController.dispose();
    _titleController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 700,
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(Icons.add_circle_outline, color: Colors.blue),
                SizedBox(width: 12),
                Text(
                  '添加在线视频',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            
            Divider(height: 32),
            
            // 表单内容
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 视频链接输入（必填）
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _videoUrlController,
                              decoration: InputDecoration(
                                labelText: '视频链接 *',
                                hintText: 'https://example.com/video.mp4 或 .m3u8',
                                border: OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(Icons.link),
                                  onPressed: _pasteFromClipboard,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return '请输入视频链接';
                                }
                                if (_urlValidationStatus == UrlValidationStatus.invalid) {
                                  return '视频链接无效';
                                }
                                return null;
                              },
                              onChanged: (value) {
                                _validateVideoUrl(value);
                              },
                            ),
                          ),
                          SizedBox(width: 8),
                          // URL验证状态按钮
                          Container(
                            width: 80,
                            height: 56,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: _buildValidationStatusButton(),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 16),
                      
                      // 嗅探页面信息选项
                      Row(
                        children: [
                          Checkbox(
                            value: _usePageSniffing,
                            onChanged: (value) {
                              setState(() {
                                _usePageSniffing = value ?? false;
                                if (!_usePageSniffing) {
                                  _pageUrlController.clear();
                                  _detectedTitle = null;
                                  _detectedVideoUrl = null;
                                  _detectedThumbnail = null;
                                }
                              });
                            },
                          ),
                          Text('嗅探页面信息（获取更好的标题和封面）'),
                        ],
                      ),
                      
                      if (_usePageSniffing) ...[
                        SizedBox(height: 16),
                        TextFormField(
                          controller: _pageUrlController,
                          decoration: InputDecoration(
                            labelText: '页面链接',
                            hintText: 'https://example.com/video-page',
                            border: OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(Icons.link),
                              onPressed: _pasteFromClipboard,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return null; // 页面URL是可选的
                            }
                            final uri = Uri.tryParse(value);
                            if (uri == null || !uri.hasAbsolutePath) {
                              return '请输入有效的URL';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            _sniffPageInfo();
                          },
                        ),
                      ],
                      
                      SizedBox(height: 16),
                      
                      // 视频标题输入
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: '视频标题 *',
                          hintText: '输入视频标题',
                          border: OutlineInputBorder(),
                          suffixIcon: _detectedTitle != null
                              ? IconButton(
                                  icon: Icon(Icons.auto_awesome),
                                  onPressed: () {
                                    _titleController.text = _detectedTitle!;
                                  },
                                  tooltip: '使用检测到的标题',
                                )
                              : null,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入视频标题';
                          }
                          return null;
                        },
                      ),
                      
                      // 检测到的信息提示
                      if (_detectedTitle != null && _titleController.text.isEmpty) ...[
                        SizedBox(height: 8),
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info, color: Colors.blue, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '检测到标题: $_detectedTitle',
                                  style: TextStyle(color: Colors.blue),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  _titleController.text = _detectedTitle!;
                                },
                                child: Text('使用'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      // 缩略图预览
                      if (_detectedThumbnail != null && _detectedThumbnail!.isNotEmpty) ...[
                        SizedBox(height: 16),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.image, color: Colors.grey[600], size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    '视频封面预览',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  _detectedThumbnail!,
                                  width: double.infinity,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      width: double.infinity,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: double.infinity,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.broken_image, color: Colors.grey),
                                          SizedBox(height: 4),
                                          Text(
                                            '封面加载失败',
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      if (_detectedVideoUrl != null && _detectedVideoUrl != _videoUrlController.text) ...[
                        SizedBox(height: 8),
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.video_library, color: Colors.green, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '检测到更好的视频链接',
                                  style: TextStyle(color: Colors.green),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  _videoUrlController.text = _detectedVideoUrl!;
                                  _validateVideoUrl(_detectedVideoUrl!);
                                },
                                child: Text('使用'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      if (_errorMessage != null) ...[
                        SizedBox(height: 16),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      if (_isLoading) ...[
                        SizedBox(height: 16),
                        Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 8),
                              Text('正在检测视频信息...'),
                            ],
                          ),
                        ),
                      ],
                      
                      SizedBox(height: 24),
                      
                      // 支持的格式说明
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '支持的视频格式',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  Chip(label: Text('MP4')),
                                  Chip(label: Text('M3U8 (HLS)')),
                                  Chip(label: Text('WebM')),
                                  Chip(label: Text('AVI')),
                                  Chip(label: Text('MKV')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // 底部按钮
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('取消'),
                ),
                SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _canConfirm() ? _addVideo : null,
                  child: _isLoading 
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  /// 构建验证状态按钮
  Widget _buildValidationStatusButton() {
    switch (_urlValidationStatus) {
      case UrlValidationStatus.none:
        return IconButton(
          icon: Icon(Icons.help_outline, color: Colors.grey),
          onPressed: () {
            if (_videoUrlController.text.isNotEmpty) {
              _validateVideoUrl(_videoUrlController.text);
            }
          },
          tooltip: '点击验证',
        );
      case UrlValidationStatus.validating:
        return Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case UrlValidationStatus.valid:
        return IconButton(
          icon: Icon(Icons.check_circle, color: Colors.green),
          onPressed: null,
          tooltip: '链接有效',
        );
      case UrlValidationStatus.invalid:
        return IconButton(
          icon: Icon(Icons.error, color: Colors.red),
          onPressed: () {
            if (_videoUrlController.text.isNotEmpty) {
              _validateVideoUrl(_videoUrlController.text);
            }
          },
          tooltip: '链接无效，点击重新验证',
        );
    }
  }
  
  /// 检查是否可以确认
  bool _canConfirm() {
    if (_isLoading) return false;
    if (_videoUrlController.text.trim().isEmpty) return false;
    if (_titleController.text.trim().isEmpty) return false;
    if (_urlValidationStatus != UrlValidationStatus.valid) return false;
    return true;
  }
  
  /// 从剪贴板粘贴
  void _pasteFromClipboard() async {
    // 这里需要实现剪贴板功能
    // 由于Flutter的剪贴板功能需要额外的包，这里先留空
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('剪贴板功能需要额外实现')),
    );
  }
  
  /// 验证视频URL
  Future<void> _validateVideoUrl(String url) async {
    if (url.isEmpty) {
      setState(() {
        _urlValidationStatus = UrlValidationStatus.none;
        _errorMessage = null;
      });
      return;
    }
    
    setState(() {
      _urlValidationStatus = UrlValidationStatus.validating;
      _errorMessage = null;
    });
    
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) {
        setState(() {
          _urlValidationStatus = UrlValidationStatus.invalid;
          _errorMessage = '无效的URL格式';
        });
        return;
      }
      
      // 检查文件扩展名
      final path = uri.path.toLowerCase();
      final supportedExtensions = ['.mp4', '.m3u8', '.webm', '.avi', '.mkv'];
      final hasValidExtension = supportedExtensions.any((ext) => path.endsWith(ext));
      
      if (!hasValidExtension) {
        setState(() {
          _urlValidationStatus = UrlValidationStatus.invalid;
          _errorMessage = '不支持的视频格式，请使用: ${supportedExtensions.join(', ')}';
        });
        return;
      }
      
      // 如果URL中没有标题信息，尝试从URL中提取
      if (_titleController.text.isEmpty) {
        final extractedTitle = _extractTitleFromUrl(url);
        if (extractedTitle.isNotEmpty) {
          setState(() {
            _detectedTitle = extractedTitle;
            _titleController.text = extractedTitle;
          });
        }
      }
      
      setState(() {
        _urlValidationStatus = UrlValidationStatus.valid;
        _errorMessage = null;
      });
      
    } catch (e) {
      setState(() {
        _urlValidationStatus = UrlValidationStatus.invalid;
        _errorMessage = 'URL验证失败: $e';
      });
    }
  }
  
  /// 嗅探页面信息
  Future<void> _sniffPageInfo() async {
    final pageUrl = _pageUrlController.text.trim();
    if (pageUrl.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _detectedTitle = null;
      _detectedVideoUrl = null;
      _detectedThumbnail = null;
    });
    
    try {
      // 使用混合服务检测视频信息
      final videoInfo = await HybridVideoSnifferService.extractVideoInfo(pageUrl);
      
      if (videoInfo != null) {
        setState(() {
          _detectedTitle = CharacterFixService.fixCharacters(videoInfo.title);
          
          // 提取最佳流和HTTP头（若为yt-dlp返回的VideoStream）
          final ytStreams = videoInfo.streams.whereType<VideoStream>().toList();
          if (ytStreams.isNotEmpty) {
            final best = VideoStreamSelector.selectBestStream(ytStreams) ?? ytStreams.first;
            _detectedVideoUrl = best.url;
            _detectedHeaders = best.httpHeaders;
          } else {
            _detectedVideoUrl = videoInfo.videoUrl;
            _detectedHeaders = null;
          }
          
          // 设置缩略图
          _detectedThumbnail = videoInfo.thumbnail;
          
          // 如果当前没有标题，自动填充检测到的标题
          if (_titleController.text.isEmpty && _detectedTitle != null) {
            _titleController.text = _detectedTitle!;
          }
          
          // 如果当前视频URL为空或无效，使用检测到的URL
          if ((_videoUrlController.text.isEmpty || !_isValidVideoUrl(_videoUrlController.text)) && _detectedVideoUrl != null) {
            _videoUrlController.text = _detectedVideoUrl!;
            _validateVideoUrl(_detectedVideoUrl!);
          }
        });
      } else {
        setState(() {
          _errorMessage = '无法从页面中检测到视频信息';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '检测失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// 检查视频URL是否有效
  bool _isValidVideoUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) return false;
      
      final path = uri.path.toLowerCase();
      final query = uri.query.toLowerCase();
      
      // 支持的视频格式扩展名
      final supportedExtensions = ['.mp4', '.m3u8', '.webm', '.avi', '.mkv', '.m4s', '.ts'];
      
      // 检查路径扩展名
      if (supportedExtensions.any((ext) => path.endsWith(ext))) {
        return true;
      }
      
      // 检查特殊的视频流格式（如Bilibili的m4s，YouTube的格式参数等）
      if (path.contains('/video/') || path.contains('/stream/') || 
          query.contains('mime=video') || query.contains('itag=') ||
          path.contains('upgcxcode') || // Bilibili特征
          uri.host.contains('googlevideo.com') || // YouTube CDN
          uri.host.contains('akamaized.net')) { // CDN服务
        return true;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }
  
  /// 检测平台类型
  String _detectPlatform(String url) {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();
    
    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return 'youtube';
    } else if (host.contains('bilibili.com')) {
      return 'bilibili';
    } else if (host.contains('missav.com') || host.contains('missav.ws')) {
      return 'missav';
    } else if (host.contains('xvideos.com')) {
      return 'xvideos';
    } else {
      return 'unknown';
    }
  }
  
  /// 从URL中提取标题
  String _extractTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      
      // 移除文件扩展名
      final pathWithoutExt = path.replaceAll(RegExp(r'\.[^.]*$'), '');
      
      // 分割路径并找到有意义的部分
      final segments = pathWithoutExt.split('/').where((segment) => 
        segment.isNotEmpty && 
        segment.length > 2 &&
        !RegExp(r'^[0-9a-f]{8,}$').hasMatch(segment) // 排除哈希值
      ).toList();
      
      if (segments.isNotEmpty) {
        // 取最后一个有意义的段作为标题
        final title = segments.last;
        // 替换下划线和连字符为空格
        return title.replaceAll(RegExp(r'[-_]'), ' ');
      }
      
      return '';
    } catch (e) {
      return '';
    }
  }
  
  /// 添加视频
  Future<void> _addVideo() async {
    
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (!_canConfirm()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final videoUrl = _videoUrlController.text.trim();
      final pageUrl = _pageUrlController.text.trim();
      final title = _titleController.text.trim();
      
      print('  - videoUrl: $videoUrl');
      print('  - pageUrl: $pageUrl'); 
      print('  - title: $title');
      
      // 创建OnlineVideo对象
      final onlineVideo = OnlineVideo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        url: pageUrl.isNotEmpty ? pageUrl : videoUrl,
        thumbnailUrl: _detectedThumbnail, // 直接设置缩略图URL
        platform: _detectPlatform(pageUrl.isNotEmpty ? pageUrl : videoUrl),
        metadata: {
          'videoUrl': videoUrl,
          if (_detectedHeaders != null) 'httpHeaders': _detectedHeaders,
          'detectedTitle': _detectedTitle,
          'detectedThumbnail': _detectedThumbnail,
          'addedAt': DateTime.now().toIso8601String(),
        },
      );
      
      
      // 返回结果
      Navigator.of(context).pop(onlineVideo);
      
    } catch (e) {
      setState(() {
        _errorMessage = '创建视频失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
