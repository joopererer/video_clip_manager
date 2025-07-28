import 'dart:io';
import 'package:flutter/material.dart';
import '../data/models.dart';

class ClipThumbnail extends StatelessWidget {
  final VideoClip clip;
  final double? size;

  const ClipThumbnail({super.key, required this.clip, this.size});

  @override
  Widget build(BuildContext context) {
    // 直接从 widget 属性获取路径，这是唯一的数据源
    final String? path = clip.thumbnailPath;

    Widget placeholder = Icon(
      Icons.movie_filter,
      size: size != null ? size! * 0.8 : 40,
      color: Colors.grey.shade400,
    );

    // 1. 如果路径为 null，说明正在生成或需要生成，显示加载指示器
    if (path == null) {
      return Center(child: CircularProgressIndicator(strokeWidth: 2.0));
    }

    // 2. 如果路径不为 null，使用 FutureBuilder 检查文件是否存在
    //    key 是解决竞态条件的关键！
    return FutureBuilder<bool>(
      key: ValueKey(path), // 当 path 改变时，Flutter会创建一个新的FutureBuilder，丢弃旧的
      future: File(path).exists(),
      builder: (context, snapshot) {
        // 3. 在检查文件存在的短暂过程中，也显示加载指示器
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(strokeWidth: 2.0));
        }

        // 4. Future 完成后，根据结果显示图片或占位符
        final bool fileExists = snapshot.data ?? false;
        if (fileExists) {
          return Image.file(
            File(path), // 此处 path 肯定不为 null
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => Center(child: placeholder),
          );
        } else {
          // 路径存在但文件不存在（可能生成失败或被删除），显示占位符
          return Center(child: placeholder);
        }
      },
    );
  }
}
