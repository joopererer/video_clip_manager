import 'package:flutter/material.dart';
import '../services/multi_source_search_service.dart';

/// 标题选择对话框
class TitleSelectionDialog extends StatefulWidget {
  final List<MultiSourceResult> results;
  final String videoCode;

  const TitleSelectionDialog({
    Key? key,
    required this.results,
    required this.videoCode,
  }) : super(key: key);

  @override
  State<TitleSelectionDialog> createState() => _TitleSelectionDialogState();
}

class _TitleSelectionDialogState extends State<TitleSelectionDialog> {
  MultiSourceResult? _selectedResult;
  bool _useRecommended = true;

  @override
  void initState() {
    super.initState();
    // 默认选择推荐结果
    _selectedResult = MultiSourceSearchService.getRecommendedResult(widget.results);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.search, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text('选择标题 - ${widget.videoCode}'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '找到 ${widget.results.length} 个不同的标题，请选择最合适的：',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.results.length,
                itemBuilder: (context, index) {
                  final result = widget.results[index];
                  final isRecommended = result == MultiSourceSearchService.getRecommendedResult(widget.results);
                  final isSelected = _selectedResult == result;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isSelected 
                        ? Theme.of(context).primaryColor.withOpacity(0.1)
                        : null,
                    child: RadioListTile<MultiSourceResult>(
                      value: result,
                      groupValue: _selectedResult,
                      onChanged: (value) {
                        setState(() {
                          _selectedResult = value;
                        });
                      },
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  result.title,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isRecommended)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '推荐',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _getSourceIcon(result.source),
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                result.source,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '置信度: ${(result.confidence * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      subtitle: result.thumbnailUrl != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  result.thumbnailUrl!,
                                  height: 60,
                                  width: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 60,
                                      width: 40,
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.image_not_supported, size: 20),
                                    );
                                  },
                                ),
                              ),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _useRecommended,
                  onChanged: (value) {
                    setState(() {
                      _useRecommended = value ?? true;
                      if (_useRecommended) {
                        _selectedResult = MultiSourceSearchService.getRecommendedResult(widget.results);
                      }
                    });
                  },
                ),
                const Expanded(
                  child: Text(
                    '记住我的选择偏好',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _selectedResult != null
              ? () => Navigator.of(context).pop(_selectedResult)
              : null,
          child: const Text('确认选择'),
        ),
      ],
    );
  }

  IconData _getSourceIcon(String source) {
    switch (source) {
      case 'MissAV (Japanese)':
      case 'MissAV (French)':
        return Icons.video_library;
      case 'JavDB':
        return Icons.storage;
      case 'JavMost':
        return Icons.star;
      case 'JavLibrary':
        return Icons.library_books;
      default:
        return Icons.info;
    }
  }
}

/// 显示标题选择对话框
Future<MultiSourceResult?> showTitleSelectionDialog(
  BuildContext context,
  List<MultiSourceResult> results,
  String videoCode,
) {
  return showDialog<MultiSourceResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => TitleSelectionDialog(
      results: results,
      videoCode: videoCode,
    ),
  );
}
