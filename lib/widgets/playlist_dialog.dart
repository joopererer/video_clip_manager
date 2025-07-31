import 'package:flutter/material.dart';
import '../data/models.dart';

class PlaylistDialog extends StatefulWidget {
  final Playlist? playlist; // null 表示创建新播放列表

  const PlaylistDialog({super.key, this.playlist});

  @override
  State<PlaylistDialog> createState() => _PlaylistDialogState();
}

class _PlaylistDialogState extends State<PlaylistDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist?.name ?? '');
    _descriptionController = TextEditingController(text: widget.playlist?.description ?? '');
    // Add listeners to trigger setState when text changes, enabling/disabling the button
    _nameController.addListener(_onInputChanged);
    _descriptionController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    // Remove listeners to prevent memory leaks
    _nameController.removeListener(_onInputChanged);
    _descriptionController.removeListener(_onInputChanged);
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // Method to call setState when input changes
  void _onInputChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.playlist != null;
    final isButtonEnabled = _nameController.text.trim().isNotEmpty;
    
    return AlertDialog(
      title: Text(isEditing ? '编辑播放列表' : '创建播放列表'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '播放列表名称',
              hintText: '输入播放列表名称',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: '描述（可选）',
              hintText: '输入播放列表描述',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: isButtonEnabled
              ? () {
                  final name = _nameController.text.trim();
                  final description = _descriptionController.text.trim().isEmpty
                      ? null
                      : _descriptionController.text.trim();
                  

                  
                  Navigator.of(context).pop(<String, String?>{
                    'name': name,
                    'description': description,
                  });
                }
              : null,
          child: Text(isEditing ? '保存' : '创建'),
        ),
      ],
    );
  }
} 