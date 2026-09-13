import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _openCtrl;
  late final TextEditingController _seekCtrl;
  late final TextEditingController _playCtrl;
  late final TextEditingController _screenshotCtrl;
  late final TextEditingController _markReadyCtrl;

  @override
  void initState() {
    super.initState();
    final appState = AppState.instance!;
    _openCtrl = TextEditingController(text: appState.openTimeoutSeconds.toString());
    _seekCtrl = TextEditingController(text: appState.seekTimeoutSeconds.toString());
    _playCtrl = TextEditingController(text: appState.playTimeoutSeconds.toString());
    _screenshotCtrl = TextEditingController(text: appState.screenshotTimeoutSeconds.toString());
    _markReadyCtrl = TextEditingController(text: appState.markReadyDelayMs.toString());
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    _seekCtrl.dispose();
    _playCtrl.dispose();
    _screenshotCtrl.dispose();
    _markReadyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final appState = context.read<AppState>();
    int? tryParse(String s) => int.tryParse(s);

    final open = tryParse(_openCtrl.text);
    final seek = tryParse(_seekCtrl.text);
    final play = tryParse(_playCtrl.text);
    final screenshot = tryParse(_screenshotCtrl.text);
    final markReady = tryParse(_markReadyCtrl.text);

    if (open == null || seek == null || play == null || screenshot == null || markReady == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请填写有效的整数值'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    // Validation ranges
    const int minTimeout = 1;
    const int maxTimeout = 120;
    const int maxPlayTimeout = 60;
    const int minMarkReady = 0;
    const int maxMarkReady = 5000;

    final errors = <String>[];
    if (open < minTimeout || open > maxTimeout) errors.add('Open timeout 必须在 $minTimeout-$maxTimeout 秒');
    if (seek < minTimeout || seek > maxTimeout) errors.add('Seek timeout 必须在 $minTimeout-$maxTimeout 秒');
    if (play < minTimeout || play > maxPlayTimeout) errors.add('Play timeout 必须在 $minTimeout-$maxPlayTimeout 秒');
    if (screenshot < minTimeout || screenshot > maxTimeout) errors.add('Screenshot timeout 必须在 $minTimeout-$maxTimeout 秒');
    if (markReady < minMarkReady || markReady > maxMarkReady) errors.add('markReady delay 必须在 $minMarkReady-$maxMarkReady 毫秒');

    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errors.join('\n')),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ));
      return;
    }

    appState.setOpenTimeoutSeconds(open);
    appState.setSeekTimeoutSeconds(seek);
    appState.setPlayTimeoutSeconds(play);
    appState.setScreenshotTimeoutSeconds(screenshot);
    appState.setMarkReadyDelayMs(markReady);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('保存成功'),
      duration: Duration(seconds: 2),
    ));
  }

  void _resetDefaults() {
    setState(() {
      _openCtrl.text = '10';
      _seekCtrl.text = '10';
      _playCtrl.text = '5';
      _screenshotCtrl.text = '15';
      _markReadyCtrl.text = '300';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Media timeouts (seconds)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildNumberField('Open timeout (s)', _openCtrl, tooltip: '等待 native 插件 open() 返回的超时时间。建议 5-30 秒。'),
              const SizedBox(height: 8),
              _buildNumberField('Seek timeout (s)', _seekCtrl, tooltip: '等待 seek 完成的超时时间。建议 5-30 秒。'),
              const SizedBox(height: 8),
              _buildNumberField('Play start timeout (s)', _playCtrl, tooltip: '启动播放的超时时间。建议 2-10 秒。'),
              const SizedBox(height: 16),
              const Text('Screenshot / metadata', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildNumberField('Screenshot timeout (s)', _screenshotCtrl, tooltip: '截图和获取时长的超时时间。建议 10-30 秒。'),
              const SizedBox(height: 8),
              _buildNumberField('markReady delay (ms)', _markReadyCtrl, tooltip: '当 off-screen video host 被重新启用时的延迟（毫秒）。增加可降低与 native 回调的竞态风险。'),
              const SizedBox(height: 24),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _resetDefaults,
                    child: const Text('Reset Defaults'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberField(String label, TextEditingController ctl, {String? tooltip}) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (tooltip != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: tooltip,
            child: const Icon(Icons.info_outline, size: 20, color: Colors.grey),
          ),
        ],
      ],
    );
  }
}
