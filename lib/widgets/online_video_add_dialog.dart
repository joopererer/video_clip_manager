import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../services/online_video_service.dart';
import '../utils/toast_utils.dart';

class OnlineVideoAddDialog extends StatefulWidget {
  const OnlineVideoAddDialog({super.key});

  @override
  State<OnlineVideoAddDialog> createState() => _OnlineVideoAddDialogState();
}

class _OnlineVideoAddDialogState extends State<OnlineVideoAddDialog> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _detectedPlatform;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _detectPlatform() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _detectedPlatform = OnlineVideoService.detectPlatform(url);
      _errorMessage = null;
    });
  }

  Future<void> _addOnlineVideo() async {
    if (!_formKey.currentState!.validate()) return;

    final url = _urlController.text.trim();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 检查外部工具是否可用
      final toolsAvailable = await OnlineVideoService.checkExternalTools();
      if (!toolsAvailable) {
        setState(() {
          _errorMessage = 'External tools not available. Please install yt-dlp and Python.';
          _isLoading = false;
        });
        return;
      }

      // 提取视频信息
      final video = await OnlineVideoService.extractVideoInfo(url);
      
      // 添加到应用状态
      final appState = context.read<AppState>();
      await appState.addOnlineVideo(video);

      if (mounted) {
        Navigator.of(context).pop(video);
        ToastUtils.showSuccess(context, 'Online video added successfully!');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to add online video: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Online Video'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Video URL',
                hintText: 'Enter YouTube, Bilibili, MissAV, or XVideos URL',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a URL';
                }
                if (!OnlineVideoService.isValidUrl(value.trim())) {
                  return 'Please enter a valid URL';
                }
                return null;
              },
              onChanged: (value) {
                if (value.trim().isNotEmpty) {
                  _detectPlatform();
                }
              },
            ),
            const SizedBox(height: 16),
            if (_detectedPlatform != null) ...[
              Row(
                children: [
                  Text('Detected Platform: '),
                  Text(
                    OnlineVideoService.getPlatformName(_detectedPlatform!),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(OnlineVideoService.getPlatformIcon(_detectedPlatform!)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    OnlineVideoService.supportsEmbeddedPlayback(_detectedPlatform!)
                        ? Icons.check_circle
                        : Icons.warning,
                    color: OnlineVideoService.supportsEmbeddedPlayback(_detectedPlatform!)
                        ? Colors.green
                        : Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    OnlineVideoService.supportsEmbeddedPlayback(_detectedPlatform!)
                        ? 'Supports embedded playback'
                        : 'Requires external player',
                    style: TextStyle(
                      fontSize: 12,
                      color: OnlineVideoService.supportsEmbeddedPlayback(_detectedPlatform!)
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Supported Platforms:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: OnlineVideoService.getSupportedPlatforms().map((platform) {
                return Chip(
                  label: Text(OnlineVideoService.getPlatformName(platform)),
                  avatar: Text(OnlineVideoService.getPlatformIcon(platform)),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addOnlineVideo,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add Video'),
        ),
      ],
    );
  }
}
