import 'package:flutter/material.dart';
import '../services/enhanced_multi_source_service.dart';

/// 标题选择对话框 - 暂时禁用，等待新的数据结构支持
class TitleSelectionDialog extends StatefulWidget {
  final String videoCode;

  const TitleSelectionDialog({Key? key, required this.videoCode})
    : super(key: key);

  @override
  State<TitleSelectionDialog> createState() => _TitleSelectionDialogState();
}

class _TitleSelectionDialogState extends State<TitleSelectionDialog> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text('标题选择 - ${widget.videoCode}'),
        ],
      ),
      content: const Text(
        '标题选择功能正在升级中，暂时使用自动选择的最佳标题。',
        style: TextStyle(fontSize: 16),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 显示标题选择对话框
Future<void> showTitleSelectionDialog(BuildContext context, String videoCode) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => TitleSelectionDialog(videoCode: videoCode),
  );
}
