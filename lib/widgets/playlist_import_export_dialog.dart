import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/app_state.dart';
import 'playlist_import_preview_dialog.dart';

class PlaylistImportExportDialog extends StatefulWidget {
  final Playlist? playlist; // 如果为null，则为导入模式；否则为导出模式

  const PlaylistImportExportDialog({super.key, this.playlist});

  @override
  State<PlaylistImportExportDialog> createState() =>
      _PlaylistImportExportDialogState();
}

class _PlaylistImportExportDialogState
    extends State<PlaylistImportExportDialog> {
  bool _isExportMode = false;
  String _selectedFilePath = '';
  String _errorMessage = '';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _isExportMode = widget.playlist != null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isExportMode ? Icons.file_download : Icons.file_upload,
            color: _isExportMode ? Colors.blue : Colors.green,
          ),
          const SizedBox(width: 8),
          Text(_isExportMode ? '导出播放列表' : '导入播放列表'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isExportMode) ...[
              _buildExportInfo(),
              const SizedBox(height: 16),
              _buildExportOptions(),
            ] else ...[
              _buildImportInfo(),
              const SizedBox(height: 16),
              _buildFileSelector(),
            ],
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildErrorMessage(),
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
          onPressed: _isProcessing ? null : _handleAction,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isExportMode ? '导出' : '导入'),
        ),
      ],
    );
  }

  Widget _buildExportInfo() {
    final playlist = widget.playlist!;
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
            '播放列表信息',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow('名称', playlist.name),
          if (playlist.description?.isNotEmpty ?? false)
            _buildInfoRow('描述', playlist.description!),
          _buildInfoRow('片段数量', '${playlist.clipCount} 个'),
          _buildInfoRow('总时长', _formatDuration(playlist.totalDuration)),
          _buildInfoRow('创建时间', _formatDate(playlist.createdAt)),
        ],
      ),
    );
  }

  Widget _buildImportInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '导入说明',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green.shade800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '• 支持从之前导出的播放列表文件导入\n'
            '• 导入的播放列表将作为新播放列表创建\n'
            '• 如果片段文件不存在，将跳过该片段\n'
            '• 建议在导入前备份现有数据',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildExportOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('导出选项', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _selectExportPath,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('选择保存位置'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade700,
                ),
              ),
            ),
          ],
        ),
        if (_selectedFilePath.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.file_present, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFilePath,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFileSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('选择文件', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _selectImportFile,
                icon: const Icon(Icons.file_open, size: 18),
                label: const Text('选择播放列表文件'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade50,
                  foregroundColor: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ),
        if (_selectedFilePath.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.file_present, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFilePath,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: Colors.red.shade600, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Future<void> _selectExportPath() async {
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '选择播放列表保存位置',
        fileName: '${widget.playlist!.name}_播放列表.json',
        allowedExtensions: ['json'],
        type: FileType.custom,
      );

      if (outputFile != null) {
        setState(() {
          _selectedFilePath = outputFile;
          _errorMessage = '';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '选择文件路径时出错: $e';
      });
    }
  }

  Future<void> _selectImportFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择播放列表文件',
        allowedExtensions: ['json'],
        type: FileType.custom,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path!;
          _errorMessage = '';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '选择文件时出错: $e';
      });
    }
  }

  Future<void> _handleAction() async {
    if (_isExportMode) {
      await _exportPlaylist();
    } else {
      await _importPlaylist();
    }
  }

  Future<void> _exportPlaylist() async {
    if (_selectedFilePath.isEmpty) {
      setState(() {
        _errorMessage = '请先选择保存位置';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = '';
    });

    try {
      final playlist = widget.playlist!;

      // 获取 AppState 来访问 clips
      final appState = Provider.of<AppState>(context, listen: false);

      // 创建导出数据
      final exportData = {
        'version': '1.0',
        'exportedAt': DateTime.now().toIso8601String(),
        'playlist': {
          'id': playlist.id,
          'name': playlist.name,
          'description': playlist.description,
          'createdAt': playlist.createdAt.toIso8601String(),
          'items': playlist.items.map((item) {
            // 尝试找到对应的 clip
            final clip = appState.clips.firstWhere(
              (c) => c.id == item.clipId,
              orElse: () =>
                  VideoClip(id: item.clipId, name: '未知片段', videoPath: ''),
            );

            return {
              'id': item.id,
              'clipId': item.clipId,
              'customStartTime': item.customStartTime?.inMilliseconds,
              'customEndTime': item.customEndTime?.inMilliseconds,
              'duration': item.duration?.inMilliseconds,
              // 添加完整的 clip 信息用于导入时重建
              'clipInfo': {
                'id': clip.id,
                'name': clip.name,
                'videoPath': clip.videoPath,
                'startTime': clip.startTime.inMilliseconds,
                'endTime': clip.endTime.inMilliseconds,
                'coverFrameTime': clip.coverFrameTime.inMilliseconds,
                'tags': clip.tags,
                'notes': clip.notes,
                'rating': clip.rating,
                'isFavorite': clip.isFavorite,
                'thumbnailPath': clip.thumbnailPath,
              },
            };
          }).toList(),
        },
      };

      // 写入文件
      final file = File(_selectedFilePath);
      await file.writeAsString(jsonEncode(exportData));

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放列表 "${playlist.name}" 导出成功！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = '导出失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _importPlaylist() async {
    if (_selectedFilePath.isEmpty) {
      setState(() {
        _errorMessage = '请先选择要导入的文件';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = '';
    });

    try {
      final file = File(_selectedFilePath);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      // 验证文件格式
      if (data['version'] == null || data['playlist'] == null) {
        throw Exception('无效的播放列表文件格式');
      }

      final playlistData = data['playlist'] as Map<String, dynamic>;

      // 创建导入的播放列表数据
      final importedPlaylist = {
        'name': playlistData['name'] ?? '导入的播放列表',
        'description': playlistData['description'],
        'items': playlistData['items'] ?? [],
      };

      if (mounted) {
        // 关闭当前对话框
        Navigator.of(context).pop();

        // 显示导入预览对话框
        final result = await showDialog<bool>(
          context: context,
          builder: (context) =>
              PlaylistImportPreviewDialog(playlistData: importedPlaylist),
        );

        // 如果用户确认导入，结果已经在预览对话框中处理了
        if (result == true) {
          // 导入成功，不需要额外操作
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = '导入失败: $e';
      });
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
