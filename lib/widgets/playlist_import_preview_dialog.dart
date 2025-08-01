import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/app_state.dart';

class PlaylistImportPreviewDialog extends StatefulWidget {
  final Map<String, dynamic> playlistData;

  const PlaylistImportPreviewDialog({
    super.key,
    required this.playlistData,
  });

  @override
  State<PlaylistImportPreviewDialog> createState() =>
      _PlaylistImportPreviewDialogState();
}

class _PlaylistImportPreviewDialogState
    extends State<PlaylistImportPreviewDialog> {
  late List<ImportItemAnalysis> _analysisResults;
  bool _createMissingClips = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _analyzeImportData();
  }

  void _analyzeImportData() {
    final appState = Provider.of<AppState>(context, listen: false);
    final items = widget.playlistData['items'] as List<dynamic>? ?? [];
    
    _analysisResults = [];
    
    for (int i = 0; i < items.length; i++) {
      final itemData = items[i] as Map<String, dynamic>;
      final clipId = itemData['clipId'] as String?;
      final clipInfo = itemData['clipInfo'] as Map<String, dynamic>?;
      
      if (clipId != null) {
        // 检查 clip 是否存在
        final existingClip = appState.clips.firstWhere(
          (c) => c.id == clipId,
          orElse: () => VideoClip(
            id: '',
            name: '',
            videoPath: '',
          ),
        );
        
        // 如果有 clipInfo，进行完整的分析
        if (clipInfo != null) {
          final videoPath = clipInfo['videoPath'] as String? ?? '';
          final videoFileExists = videoPath.isNotEmpty && File(videoPath).existsSync();
          
          _analysisResults.add(ImportItemAnalysis(
            index: i,
            clipId: clipId,
            clipName: clipInfo['name'] as String? ?? '未知片段',
            videoPath: videoPath,
            existingClip: existingClip.id.isNotEmpty ? existingClip : null,
            videoFileExists: videoFileExists,
            customStartTime: _parseDuration(itemData['customStartTime']),
            customEndTime: _parseDuration(itemData['customEndTime']),
            duration: _parseDuration(itemData['duration']),
          ));
        } else {
          // 旧格式数据，只检查clip是否存在
          _analysisResults.add(ImportItemAnalysis(
            index: i,
            clipId: clipId,
            clipName: '片段 $clipId',
            videoPath: '',
            existingClip: existingClip.id.isNotEmpty ? existingClip : null,
            videoFileExists: false, // 旧格式无法检查视频文件
            customStartTime: _parseDuration(itemData['customStartTime']),
            customEndTime: _parseDuration(itemData['customEndTime']),
            duration: _parseDuration(itemData['duration']),
          ));
        }
      }
    }
  }

  Duration? _parseDuration(dynamic value) {
    if (value == null) return null;
    if (value is int) return Duration(milliseconds: value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final missingClips = _analysisResults.where((item) => item.existingClip == null).length;
    final existingClips = _analysisResults.where((item) => item.existingClip != null).length;
    final missingVideos = _analysisResults.where((item) => 
      item.existingClip == null && !item.videoFileExists).length;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.preview, color: Colors.blue),
          const SizedBox(width: 8),
          const Text('导入预览'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCard(existingClips, missingClips, missingVideos),
            const SizedBox(height: 16),
            Expanded(
              child: _buildAnalysisList(),
            ),
            if (missingClips > 0) ...[
              const SizedBox(height: 16),
              _buildOptionsCard(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _handleImport,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('开始导入'),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(int existingClips, int missingClips, int missingVideos) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '播放列表: ${widget.playlistData['name'] ?? '导入的播放列表'}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSummaryItem('总片段', _analysisResults.length, Colors.blue),
              const SizedBox(width: 16),
              _buildSummaryItem('已存在', existingClips, Colors.green),
              const SizedBox(width: 16),
              _buildSummaryItem('缺失片段', missingClips, Colors.orange),
              if (missingVideos > 0) ...[
                const SizedBox(width: 16),
                _buildSummaryItem('缺失视频文件', missingVideos, Colors.red),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildAnalysisList() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: _analysisResults.length,
        itemBuilder: (context, index) {
          final item = _analysisResults[index];
          return _buildAnalysisItem(item);
        },
      ),
    );
  }

  Widget _buildAnalysisItem(ImportItemAnalysis item) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (item.existingClip != null) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = '已存在';
    } else if (item.videoFileExists) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
      statusText = '可创建';
    } else if (item.videoPath.isEmpty) {
      // 旧格式数据，无法检查视频文件
      statusColor = Colors.grey;
      statusIcon = Icons.help_outline;
      statusText = '无法检查';
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.error;
      statusText = '视频文件缺失';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.clipName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  item.videoPath.isNotEmpty 
                      ? item.videoPath 
                      : '旧格式数据，无视频路径信息',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.duration != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '时长: ${_formatDuration(item.duration!)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                '导入选项',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            title: const Text('自动创建缺失的片段'),
            subtitle: const Text('如果视频文件存在，将自动创建对应的片段'),
            value: _createMissingClips,
            onChanged: (value) {
              setState(() {
                _createMissingClips = value ?? true;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Future<void> _handleImport() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      
      // 创建缺失的 clips（如果需要）
      if (_createMissingClips) {
        for (final item in _analysisResults) {
          if (item.existingClip == null && item.videoFileExists) {
            // 从原始数据中重建 clip
            final itemsData = widget.playlistData['items'] as List<dynamic>;
            final itemData = itemsData[item.index] as Map<String, dynamic>;
            final clipInfo = itemData['clipInfo'] as Map<String, dynamic>?;
            
            // 只有新格式数据才包含clipInfo，可以创建缺失的片段
            if (clipInfo != null) {
              final clip = VideoClip(
                id: clipInfo['id'] as String,
                name: clipInfo['name'] as String? ?? '导入的片段',
                videoPath: clipInfo['videoPath'] as String,
                startTime: Duration(milliseconds: clipInfo['startTime'] as int? ?? 0),
                endTime: Duration(milliseconds: clipInfo['endTime'] as int? ?? 0),
                coverFrameTime: Duration(milliseconds: clipInfo['coverFrameTime'] as int? ?? 0),
                tags: List<String>.from(clipInfo['tags'] as List<dynamic>? ?? []),
                notes: clipInfo['notes'] as String?,
                rating: clipInfo['rating'] as int? ?? 0,
                isFavorite: clipInfo['isFavorite'] as bool? ?? false,
                thumbnailPath: clipInfo['thumbnailPath'] as String?,
              );
              
              await appState.addClip(clip);
            }
            // 旧格式数据无法创建缺失的片段，因为缺少必要的clip信息
          }
        }
      }
      
      // 导入播放列表
      appState.importPlaylist(widget.playlistData);
      
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放列表 "${widget.playlistData['name']}" 导入成功！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}

class ImportItemAnalysis {
  final int index;
  final String clipId;
  final String clipName;
  final String videoPath;
  final VideoClip? existingClip;
  final bool videoFileExists;
  final Duration? customStartTime;
  final Duration? customEndTime;
  final Duration? duration;

  ImportItemAnalysis({
    required this.index,
    required this.clipId,
    required this.clipName,
    required this.videoPath,
    this.existingClip,
    required this.videoFileExists,
    this.customStartTime,
    this.customEndTime,
    this.duration,
  });
} 