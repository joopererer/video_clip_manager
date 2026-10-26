import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_state.dart';
import '../data/models.dart';

class AddToPlaylistDialog extends StatefulWidget {
  final VideoClip clip;

  const AddToPlaylistDialog({super.key, required this.clip});

  @override
  State<AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends State<AddToPlaylistDialog> {
  Playlist? _selectedPlaylist;
  bool _isCreatingNew = false;
  final _newPlaylistNameController = TextEditingController();
  final _newPlaylistDescriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _newPlaylistNameController.addListener(_onInputChanged);
    _newPlaylistDescriptionController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _newPlaylistNameController.removeListener(_onInputChanged);
    _newPlaylistDescriptionController.removeListener(_onInputChanged);
    _newPlaylistNameController.dispose();
    _newPlaylistDescriptionController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final playlists = appState.playlists;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.playlist_add, color: Colors.blue.shade600),
          const SizedBox(width: 8),
          const Text('添加到播放列表'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Clip 信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.video_file, color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.clip.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '时长: ${_formatDuration(widget.clip.endTime - widget.clip.startTime)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 选择方式
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('选择现有播放列表'),
                    value: false,
                    groupValue: _isCreatingNew,
                    onChanged: (value) {
                      setState(() {
                        _isCreatingNew = value!;
                        _selectedPlaylist = null;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('创建新播放列表'),
                    value: true,
                    groupValue: _isCreatingNew,
                    onChanged: (value) {
                      setState(() {
                        _isCreatingNew = value!;
                        _selectedPlaylist = null;
                      });
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 现有播放列表选择
            if (!_isCreatingNew) ...[
              Text(
                '选择播放列表:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              if (playlists.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade600),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '还没有播放列表，请先创建一个',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final isSelected = _selectedPlaylist?.id == playlist.id;

                      return ListTile(
                        leading: Icon(
                          Icons.playlist_play,
                          color: isSelected
                              ? Colors.blue.shade600
                              : Colors.grey.shade600,
                        ),
                        title: Text(
                          playlist.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? Colors.blue.shade600 : null,
                          ),
                        ),
                        subtitle: Text(
                          '${playlist.clipCount} 个片段 • ${_formatDuration(playlist.totalDuration)}',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Colors.blue.shade600,
                              )
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedPlaylist = playlist;
                          });
                        },
                      );
                    },
                  ),
                ),
            ],

            // 创建新播放列表
            if (_isCreatingNew) ...[
              Text(
                '新播放列表信息:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newPlaylistNameController,
                decoration: const InputDecoration(
                  labelText: '播放列表名称',
                  hintText: '输入播放列表名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newPlaylistDescriptionController,
                decoration: const InputDecoration(
                  labelText: '描述 (可选)',
                  hintText: '输入播放列表描述',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _canAdd() ? _addToPlaylist : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
          ),
          child: const Text('添加'),
        ),
      ],
    );
  }

  bool _canAdd() {
    if (_isCreatingNew) {
      return _newPlaylistNameController.text.trim().isNotEmpty;
    } else {
      return _selectedPlaylist != null;
    }
  }

  void _addToPlaylist() {
    final appState = context.read<AppState>();

    if (_isCreatingNew) {
      // 创建新播放列表并添加 clip
      appState.createPlaylist(
        _newPlaylistNameController.text.trim(),
        description: _newPlaylistDescriptionController.text.trim(),
      );
      // 获取刚创建的播放列表
      final createdPlaylist = appState.playlists.last;
      appState.addClipToPlaylist(createdPlaylist.id, widget.clip.id);
    } else {
      // 添加到现有播放列表
      appState.addClipToPlaylist(_selectedPlaylist!.id, widget.clip.id);
    }

    Navigator.of(context).pop();

    // 显示成功消息
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isCreatingNew
              ? '已创建新播放列表并添加片段'
              : '已添加到播放列表 "${_selectedPlaylist!.name}"',
        ),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
