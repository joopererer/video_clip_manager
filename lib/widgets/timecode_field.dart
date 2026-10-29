import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/timecode.dart';

/// Returns an error message for an unacceptable [candidate], or `null`.
typedef TimecodeValidator = String? Function(Duration candidate);

/// Editable `HH:MM:SS.mmm` field for an *absolute source time*.
///
/// * Enter commits; invalid text keeps focus and shows the reason.
/// * Losing focus commits valid text, or silently reverts invalid text.
/// * Esc reverts. Up/Down nudge by 100 ms (Shift 1 s, Ctrl 10 ms); the
///   nudged value still goes through [validator].
class TimecodeField extends StatefulWidget {
  final String label;
  final Duration value;
  final ValueChanged<Duration> onCommitted;
  final TimecodeValidator? validator;
  final Color? accent;
  final bool enabled;
  final double width;

  const TimecodeField({
    super.key,
    required this.label,
    required this.value,
    required this.onCommitted,
    this.validator,
    this.accent,
    this.enabled = true,
    this.width = 148,
  });

  @override
  State<TimecodeField> createState() => _TimecodeFieldState();
}

class _TimecodeFieldState extends State<TimecodeField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  String? _error;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: formatTimecode(widget.value));
    _focus = FocusNode(onKeyEvent: _onKey)..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(TimecodeField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_dirty) _setText(widget.value);
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _setText(Duration v) => _controller.text = formatTimecode(v);

  void _revert() {
    _dirty = false;
    _setText(widget.value);
    if (_error != null) setState(() => _error = null);
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else if (_dirty && !_commit(_controller.text)) {
      _revert();
    }
  }

  bool _commit(String text) {
    final parsed = parseTimecode(text);
    final error = parsed == null
        ? 'Use HH:MM:SS.mmm'
        : widget.validator?.call(parsed);
    if (error != null) {
      setState(() => _error = error);
      return false;
    }
    setState(() => _error = null);
    _dirty = false;
    _setText(parsed!);
    widget.onCommitted(parsed);
    return true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _revert();
      return KeyEventResult.handled;
    }
    final up = key == LogicalKeyboardKey.arrowUp;
    if (!up && key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final step = keys.isControlPressed
        ? const Duration(milliseconds: 10)
        : keys.isShiftPressed
        ? const Duration(seconds: 1)
        : const Duration(milliseconds: 100);
    final base = parseTimecode(_controller.text) ?? widget.value;
    var next = up ? base + step : base - step;
    if (next.isNegative) next = Duration.zero;
    _controller.text = formatTimecode(next);
    _dirty = true;
    _commit(_controller.text);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        style: AppTypography.timecode(fontSize: 13, color: colors.textPrimary),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9:.,：。．]')),
        ],
        onChanged: (_) {
          _dirty = true;
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (v) {
          if (!_commit(v)) _focus.requestFocus();
        },
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: TextStyle(color: widget.accent ?? colors.textSecondary),
          isDense: true,
          errorText: _error,
          errorMaxLines: 2,
          errorStyle: TextStyle(color: colors.danger, fontSize: 11),
        ),
      ),
    );
  }
}
