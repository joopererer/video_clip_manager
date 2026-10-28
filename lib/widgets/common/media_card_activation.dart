import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Recognises a second tap on the same card within [window]. Selection stays
/// instant, unlike `onDoubleTap`, which delays the first tap.
class DoubleTapTracker {
  DoubleTapTracker({this.window = const Duration(milliseconds: 350)});

  final Duration window;
  Timer? _timer;

  /// Registers a tap; returns true when it completes a double tap.
  bool registerTap() {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      _timer = null;
      return true;
    }
    _timer = Timer(window, () {});
    return false;
  }

  /// Forgets a pending first tap.
  void reset() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => reset();
}

/// The single interaction policy shared by every media card and row
/// (clips, original videos, playlists):
///
/// * click: select immediately;
/// * double click: play, exactly once;
/// * Enter on the focused card (keyboard equivalent of a double click): play;
/// * right click: select and open the context menu (handled by the card);
/// * inner buttons keep their own gestures and never reach the card.
///
/// Usage: give the card's `InkWell` [focusNode] and route `onTap` through
/// [handleTap]; put [handleKey] on the surrounding `Focus.onKeyEvent`.
class MediaCardActivation {
  MediaCardActivation({DoubleTapTracker? tracker})
    : _tracker = tracker ?? DoubleTapTracker();

  final DoubleTapTracker _tracker;

  /// Focus node of the card surface. Enter is only treated as "play" while
  /// this node itself has primary focus, so Enter on an inner button (favorite,
  /// rating, menu) still activates that button instead of playing the card.
  final FocusNode focusNode = FocusNode(debugLabel: 'MediaCardSurface');

  /// Selection happens first and unconditionally; [onPlay] only fires for the
  /// second tap of a double click.
  void handleTap({VoidCallback? onSelect, required VoidCallback onPlay}) {
    onSelect?.call();
    if (_tracker.registerTap()) onPlay();
  }

  KeyEventResult handleKey(KeyEvent event, VoidCallback onPlay) {
    if (event is! KeyDownEvent || !focusNode.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _tracker.reset();
      onPlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void dispose() {
    _tracker.dispose();
    focusNode.dispose();
  }
}

/// Tap surface used by every media card/row. Replaces the card-level
/// `InkWell` so all pages share one click policy (see [MediaCardActivation]).
///
/// Buttons placed inside [child] keep their own gestures: they win the tap
/// arena, so they never select or play the card.
class MediaCardInteractor extends StatefulWidget {
  const MediaCardInteractor({
    super.key,
    required this.onActivate,
    required this.child,
    this.onSelect,
    this.onSecondaryTapDown,
    this.borderRadius,
    this.hoverColor,
  });

  /// Called on single click and on right click, before anything else.
  final VoidCallback? onSelect;

  /// Called once per double click, or Enter while the card surface is focused.
  final VoidCallback onActivate;

  /// Right click. The card is selected first; the callback opens the menu.
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Widget child;

  @override
  State<MediaCardInteractor> createState() => _MediaCardInteractorState();
}

class _MediaCardInteractorState extends State<MediaCardInteractor> {
  final _activation = MediaCardActivation();

  @override
  void dispose() {
    _activation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => _activation.handleKey(event, widget.onActivate),
      child: InkWell(
        focusNode: _activation.focusNode,
        borderRadius: widget.borderRadius,
        hoverColor: widget.hoverColor,
        onTap: () => _activation.handleTap(
          onSelect: widget.onSelect,
          onPlay: widget.onActivate,
        ),
        onSecondaryTapDown: widget.onSecondaryTapDown == null
            ? null
            : (d) {
                widget.onSelect?.call();
                widget.onSecondaryTapDown!(d);
              },
        child: widget.child,
      ),
    );
  }
}
