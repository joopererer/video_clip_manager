import 'package:flutter/material.dart';
import '../data/models.dart';

enum VideoImportOption {
  wholeVideo, // 整个视频作为clip
  createClips, // 创建片段
}

class VideoImportDialog extends StatelessWidget {
  final OriginalVideo video;

  const VideoImportDialog({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    final hasMetadata =
        video.duration != null &&
        video.duration != Duration.zero &&
        video.thumbnailPath != null;

    return AlertDialog(
      title: const Text('导入视频'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('视频: ${video.name}'),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                hasMetadata ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: hasMetadata ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                hasMetadata ? '元数据已就绪' : '元数据处理中...',
                style: TextStyle(
                  fontSize: 12,
                  color: hasMetadata ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('请选择导入方式:'),
          const SizedBox(height: 8),
          _buildOption(
            context,
            VideoImportOption.wholeVideo,
            '整个视频作为片段',
            '将整个视频作为一个clip添加到片段库中',
            Icons.video_file,
            Colors.green,
          ),
          const SizedBox(height: 8),
          _buildOption(
            context,
            VideoImportOption.createClips,
            '创建片段',
            '打开片段编辑器，手动创建多个片段',
            Icons.content_cut,
            Colors.blue,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildOption(
    BuildContext context,
    VideoImportOption option,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(option),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
