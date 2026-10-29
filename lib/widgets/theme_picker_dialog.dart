import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../theme/app_palettes.dart';
import '../theme/theme_controller.dart';

/// 外观与配色选择对话框：内置预设 + 自定义强调色，选择后即时生效并持久化。
class ThemePickerDialog extends StatefulWidget {
  const ThemePickerDialog({super.key});

  @override
  State<ThemePickerDialog> createState() => _ThemePickerDialogState();
}

class _ThemePickerDialogState extends State<ThemePickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(context.read<ThemeController>().customAccent);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final c = context.appColors;

    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(c),
            Divider(height: 1, color: c.borderSubtle),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(c, '预设方案'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final p in AppPalette.presets)
                          _PresetCard(
                            palette: p,
                            selected:
                                !controller.isCustom &&
                                controller.paletteId == p.id,
                            onTap: () => controller.selectPreset(p.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle(c, '自定义强调色'),
                    const SizedBox(height: 4),
                    Text(
                      '拖动滑块选择颜色，背景与表面色会按色相自动协调生成。',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    _customPicker(c, controller),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: c.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('恢复默认'),
                    onPressed: () {
                      controller.selectPreset(AppPalette.defaultId);
                      setState(() {
                        _hsv = HSVColor.fromColor(
                          AppPalette.defaultCustomAccent,
                        );
                      });
                    },
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppColorExtension c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.palette_outlined, color: c.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '外观与配色',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '选择一套预设，或自定义你的专属强调色',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            icon: Icon(Icons.close, color: c.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(AppColorExtension c, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: c.textPrimary,
    ),
  );

  Widget _customPicker(AppColorExtension c, ThemeController controller) {
    final preview = AppPalette.custom(_hsv.toColor());
    final selected = controller.isCustom;

    void apply() => controller.setCustomAccent(_hsv.toColor());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceElevated.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? c.primary : c.borderSubtle,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MiniPreview(colors: preview.colors, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _slider(
                      c,
                      label: '色相',
                      value: _hsv.hue,
                      max: 360,
                      activeColor: _hsv.toColor(),
                      onChanged: (v) {
                        setState(() => _hsv = _hsv.withHue(v));
                      },
                      onChangeEnd: (_) => apply(),
                    ),
                    _slider(
                      c,
                      label: '饱和度',
                      value: _hsv.saturation,
                      max: 1,
                      activeColor: _hsv.toColor(),
                      onChanged: (v) {
                        setState(() => _hsv = _hsv.withSaturation(v));
                      },
                      onChangeEnd: (_) => apply(),
                    ),
                    _slider(
                      c,
                      label: '明度',
                      value: _hsv.value,
                      max: 1,
                      activeColor: _hsv.toColor(),
                      onChanged: (v) {
                        setState(() => _hsv = _hsv.withValue(v));
                      },
                      onChangeEnd: (_) => apply(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '#${_hsv.toColor().toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12.5,
                  color: c.textSecondary,
                ),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: apply,
                child: Text(selected ? '已应用，点击更新' : '应用自定义配色'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slider(
    AppColorExtension c, {
    required String label,
    required double value,
    required double max,
    required Color activeColor,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max).toDouble(),
            min: 0,
            max: max,
            activeColor: activeColor,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _PresetCard({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final pc = palette.colors;

    return Semantics(
      button: true,
      selected: selected,
      label: '配色方案 ${palette.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 176,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.surfaceElevated.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? c.primary : c.borderSubtle,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniPreview(colors: pc, height: 64),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      palette.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, size: 18, color: c.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 迷你工作台预览：背景、侧边栏、卡片与强调色块。
class _MiniPreview extends StatelessWidget {
  final AppColorExtension colors;
  final double? size;
  final double? height;

  const _MiniPreview({required this.colors, this.size, this.height});

  @override
  Widget build(BuildContext context) {
    final h = height ?? size ?? 56;
    return Container(
      width: size,
      height: h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: (size ?? 176) * 0.2,
            color: colors.sidebar,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 6,
                    width: 28,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.borderSubtle),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
