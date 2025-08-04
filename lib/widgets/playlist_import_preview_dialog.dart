import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models.dart';
import '../data/app_state.dart';

String _formatDuration(Duration d) {
  final parts = d.toString().split('.').first.padLeft(8, '0').split(':');
  return '${parts[0]}:${parts[1]}:${parts[2]}';
}

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
        final existingClip = appState.clips.firstWhereOrNull((c) => c.id == clipId);
        
        if (clipInfo != null) {
          final videoPath = clipInfo['videoPath'] as String? ?? '';
          final videoFileExists = videoPath.isNotEmpty && File(videoPath).existsSync();
          
          _analysisResults.add(ImportItemAnalysis(
            index: i,
            clipId: clipId,
            clipName: clipInfo['name'] as String? ?? 'Unknown Clip',
            videoPath: videoPath,
            existingClip: existingClip,
            videoFileExists: videoFileExists,
          ));
        } else {
          _analysisResults.add(ImportItemAnalysis(
            index: i,
            clipId: clipId,
            clipName: 'Clip $clipId (Legacy)',
            videoPath: '',
            existingClip: existingClip,
            videoFileExists: false,
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final missingClips = _analysisResults.where((item) => item.existingClip == null).length;
    final existingClips = _analysisResults.length - missingClips;

    return AlertDialog(
      title: const Text('Import Playlist Preview'),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            Text('Playlist: ${widget.playlistData['name'] ?? 'Imported Playlist'}'),
            Text('Found $existingClips existing clips and $missingClips missing clips.'),
            Expanded(
              child: ListView.builder(
                itemCount: _analysisResults.length,
                itemBuilder: (context, index) {
                  final item = _analysisResults[index];
                  return ListTile(
                    leading: Icon(
                      item.existingClip != null ? Icons.check_circle : (item.videoFileExists ? Icons.warning : Icons.error),
                      color: item.existingClip != null ? Colors.green : (item.videoFileExists ? Colors.orange : Colors.red),
                    ),
                    title: Text(item.clipName),
                    subtitle: Text(item.videoPath.isNotEmpty ? item.videoPath : "No video path info"),
                  );
                },
              ),
            ),
            if (missingClips > 0)
              CheckboxListTile(
                title: const Text('Create missing clips if video file exists'),
                value: _createMissingClips,
                onChanged: (value) {
                  setState(() {
                    _createMissingClips = value ?? true;
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _handleImport,
          child: _isProcessing
              ? const CircularProgressIndicator()
              : const Text('Import'),
        ),
      ],
    );
  }

  Future<void> _handleImport() async {
    setState(() => _isProcessing = true);

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      
      if (_createMissingClips) {
        for (final item in _analysisResults) {
          if (item.existingClip == null && item.videoFileExists) {
            final itemsData = widget.playlistData['items'] as List<dynamic>;
            final itemData = itemsData[item.index] as Map<String, dynamic>;
            final clipInfo = itemData['clipInfo'] as Map<String, dynamic>?;
            
            if (clipInfo != null) {
              final clip = VideoClip.fromJson(clipInfo);
              await appState.addClip(clip);
            }
          }
        }
      }
      
      appState.importPlaylist(widget.playlistData);
      
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playlist "${widget.playlistData['name']}" imported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
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

  ImportItemAnalysis({
    required this.index,
    required this.clipId,
    required this.clipName,
    required this.videoPath,
    this.existingClip,
    required this.videoFileExists,
  });
}
