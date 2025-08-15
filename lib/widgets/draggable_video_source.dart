import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class DraggableVideoSource extends StatelessWidget {
  final String videoPath;
  final Widget child;

  const DraggableVideoSource({
    super.key,
    required this.videoPath,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: 'video:$videoPath',
      feedback: Material(
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                p.basename(videoPath),
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: child),
      child: child,
    );
  }
}
