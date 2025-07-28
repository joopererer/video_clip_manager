import 'dart:io';
import 'package:flutter/material.dart';
import '../data/models.dart';

class ClipThumbnail extends StatelessWidget {
  final VideoClip clip;
  final double? size;

  const ClipThumbnail({super.key, required this.clip, this.size});

  @override
  Widget build(BuildContext context) {
    // This will be the content: an image, a loader, or a placeholder icon.
    Widget child;

    final String? path = clip.thumbnailPath;
    Widget placeholder = Icon(
      Icons.movie_filter,
      size: size != null ? size! * 0.8 : 40,
      color: Colors.grey.shade400,
    );

    if (path == null) {
      child = Center(child: CircularProgressIndicator(strokeWidth: 2.0));
    } else {
      child = FutureBuilder<bool>(
        key: ValueKey(path),
        future: File(path).exists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(strokeWidth: 2.0));
          }

          final bool fileExists = snapshot.data ?? false;
          if (fileExists) {
            return Image.file(
              File(path),
              fit: BoxFit.cover,
              // Make the image fill its container (the SizedBox or GridTile)
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (c, e, s) => Center(child: placeholder),
            );
          } else {
            return Center(child: placeholder);
          }
        },
      );
    }

    // If a size is provided (like in the ListView), wrap the child
    // in a SizedBox with fixed dimensions.
    if (size != null) {
      return SizedBox(width: size, height: size, child: child);
    }

    // Otherwise (like in the GridView), return the child directly
    // to let it be sized by its parent (the GridTile).
    return child;
  }
}
