import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/timecode.dart';

/// Player-level commands the clip editor can trigger from the keyboard.
enum ClipEditorCommand {
  togglePlay,
  setIn,
  setOut,
  seekBack,
  seekForward,
  toggleMute,
  setCover,
  toggleHints,
}

/// A resolved key press. [step] is only set for seek commands.
class ClipEditorKeyBinding {
  const ClipEditorKeyBinding(this.command, [this.step]);

  final ClipEditorCommand command;
  final Duration? step;

  @override
  bool operator ==(Object other) =>
      other is ClipEditorKeyBinding &&
      other.command == command &&
      other.step == step;

  @override
  int get hashCode => Object.hash(command, step);
}

/// Maps a key + modifiers to an editor command, or `null`.
///
/// Single-letter commands never match while Ctrl/Alt/Meta/Shift is held, so
/// Ctrl+S (save) cannot toggle mute and Ctrl+C keeps meaning "copy".
/// Arrow nudging: Shift = 1 s, Ctrl = 10 ms, otherwise 100 ms. These are time
/// steps, not frame steps.
ClipEditorKeyBinding? resolveClipEditorKey(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool control = false,
  bool alt = false,
  bool meta = false,
}) {
  if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight) {
    if (alt || meta) return null;
    final step = NudgeStep.forModifiers(shift: shift, control: control);
    return ClipEditorKeyBinding(
      key == LogicalKeyboardKey.arrowLeft
          ? ClipEditorCommand.seekBack
          : ClipEditorCommand.seekForward,
      step,
    );
  }
  if (key == LogicalKeyboardKey.f1) {
    return const ClipEditorKeyBinding(ClipEditorCommand.toggleHints);
  }
  if (control || alt || meta || shift) return null;
  if (key == LogicalKeyboardKey.space) {
    return const ClipEditorKeyBinding(ClipEditorCommand.togglePlay);
  }
  if (key == LogicalKeyboardKey.keyI || key == LogicalKeyboardKey.digit1) {
    return const ClipEditorKeyBinding(ClipEditorCommand.setIn);
  }
  if (key == LogicalKeyboardKey.keyO || key == LogicalKeyboardKey.digit2) {
    return const ClipEditorKeyBinding(ClipEditorCommand.setOut);
  }
  if (key == LogicalKeyboardKey.keyS) {
    return const ClipEditorKeyBinding(ClipEditorCommand.toggleMute);
  }
  if (key == LogicalKeyboardKey.keyC) {
    return const ClipEditorKeyBinding(ClipEditorCommand.setCover);
  }
  return null;
}

/// True when [node] (default: the primary focus) is inside a text field, so
/// typed characters, caret movement and IME composition belong to the field.
bool isTextInputFocused([FocusNode? node]) {
  final context = (node ?? FocusManager.instance.primaryFocus)?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// True when [node] is a button-like control that owns Space activation.
bool isActivatableControlFocused([FocusNode? node]) {
  final context = (node ?? FocusManager.instance.primaryFocus)?.context;
  if (context == null) return false;
  if (_isActivatable(context.widget)) return true;
  var found = false;
  context.visitAncestorElements((element) {
    if (element.widget is ClipEditorKeyHandler) return false;
    if (_isActivatable(element.widget)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

bool _isActivatable(Widget widget) =>
    widget is ButtonStyleButton ||
    widget is IconButton ||
    widget is Checkbox ||
    widget is Switch ||
    widget is Radio;

/// Focus scope that forwards editor shortcuts while nothing else owns the
/// keyboard.
///
/// Shortcuts are ignored while a text field (including IME composition) has
/// focus. Space is additionally ignored while a button has focus, so keyboard
/// users can still activate it.
class ClipEditorKeyHandler extends StatelessWidget {
  const ClipEditorKeyHandler({
    super.key,
    required this.focusNode,
    required this.onCommand,
    required this.child,
    this.enabled = true,
  });

  final FocusNode focusNode;
  final bool enabled;
  final void Function(ClipEditorCommand command, Duration? step) onCommand;
  final Widget child;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final binding = resolveClipEditorKey(
      event.logicalKey,
      shift: keys.isShiftPressed,
      control: keys.isControlPressed,
      alt: keys.isAltPressed,
      meta: keys.isMetaPressed,
    );
    if (binding == null) return KeyEventResult.ignored;

    final primary = FocusManager.instance.primaryFocus;
    if (isTextInputFocused(primary)) return KeyEventResult.ignored;
    if (binding.command == ClipEditorCommand.togglePlay &&
        isActivatableControlFocused(primary)) {
      return KeyEventResult.ignored;
    }
    final isSeek =
        binding.command == ClipEditorCommand.seekBack ||
        binding.command == ClipEditorCommand.seekForward;
    // Held keys repeat only for seeking; toggles fire once per press.
    if (event is KeyRepeatEvent && !isSeek) return KeyEventResult.handled;
    onCommand(binding.command, binding.step);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: child,
    );
  }
}

/// Hands the keyboard back to [focusNode] after a click, unless the click
/// landed inside the text field that currently has focus.
///
/// Wrap the non-text parts of the editor (video stage, transport) so
/// shortcuts keep working after mouse use, while clicking into a field keeps
/// the caret.
class KeyboardClaimRegion extends StatelessWidget {
  const KeyboardClaimRegion({
    super.key,
    required this.focusNode,
    required this.child,
  });

  final FocusNode focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (event) {
        final position = event.position;
        // After the click's own handlers (button focus, field focus) ran.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!focusNode.canRequestFocus || focusNode.hasPrimaryFocus) return;
          final primary = FocusManager.instance.primaryFocus;
          if (isTextInputFocused(primary)) {
            final box = primary?.context?.findRenderObject();
            if (box is RenderBox && box.attached) {
              final rect = (box.localToGlobal(Offset.zero) & box.size).inflate(
                24,
              );
              if (rect.contains(position)) return;
            }
          }
          focusNode.requestFocus();
        });
      },
      child: child,
    );
  }
}
