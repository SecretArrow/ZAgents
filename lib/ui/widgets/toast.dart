import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Non-intrusive replacement for SnackBar (v1.49.5).
///
/// A small dark pill floats near the bottom of the screen: it fades in,
/// holds briefly and fades out. Unlike a SnackBar it never reserves layout
/// space, never pushes content (or the composer) up, and it IGNORES pointer
/// events so it can never intercept a tap while it is visible.
///
/// The hold phase deliberately uses a [Timer] (exactly like SnackBar does)
/// while the fades use an [AnimationController]. Widget tests that settle
/// with `pumpAndSettle` therefore find the toast STILL VISIBLE afterwards —
/// the same contract the old SnackBar-based flows were written against —
/// and the fade animations always settle on their own.
OverlayEntry? _currentToast;

/// Shows [message] as a subtle toast. Calling it again while a toast is
/// visible replaces the current one immediately — the same cadence the old
/// `..hideCurrentSnackBar() ..showSnackBar(...)` chains had.
void showToast(
  BuildContext context,
  String message, {
  Key? key,
  Duration duration = const Duration(milliseconds: 2600),
}) {
  final String text = message.trim();
  if (text.isEmpty) return;
  // rootOverlay: toasts must surface above bottom sheets and dialogs too.
  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _dropCurrent();
  // late: the builder closure reads `entry`, so the variable must already
  // be DECLARED when the closure is created (it only ever RUNS after the
  // entry is inserted below).
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext overlayContext) => _ToastCard(
      key: key ?? const ValueKey<String>('toast-card'),
      message: text,
      holdDuration: duration,
      onExpired: () => _removeToast(entry),
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
}

void _removeToast(OverlayEntry entry) {
  if (!identical(_currentToast, entry)) return;
  _currentToast = null;
  if (entry.mounted) entry.remove();
}

void _dropCurrent() {
  final OverlayEntry? old = _currentToast;
  _currentToast = null;
  if (old != null && old.mounted) old.remove();
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required super.key,
    required this.message,
    required this.holdDuration,
    required this.onExpired,
  });

  final String message;
  final Duration holdDuration;
  final VoidCallback onExpired;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  static const Duration _fadeIn = Duration(milliseconds: 160);
  static const Duration _fadeOut = Duration(milliseconds: 220);

  late final AnimationController _fade;
  Timer? _holdTimer;
  bool _fadingOut = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: _fadeIn)
      ..addStatusListener(_onFadeStatus)
      ..forward();
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      // Fade-in done → hold, then fade out. The hold is a Timer (SnackBar
      // parity): pumpAndSettle in widget tests must NOT burn it away.
      _holdTimer?.cancel();
      _holdTimer = Timer(widget.holdDuration, _beginFadeOut);
    } else if (status == AnimationStatus.dismissed && _fadingOut) {
      widget.onExpired();
    }
  }

  void _beginFadeOut() {
    if (!mounted || _fadingOut) return;
    _fadingOut = true;
    _fade
      ..duration = _fadeOut
      ..reverse();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    // Stay clear of the system gesture inset and float ABOVE the keyboard
    // when the composer has it open.
    final double bottom =
        math.max(mq.viewInsets.bottom, mq.padding.bottom) + 28.0;
    final double maxWidth = math.min(560.0, mq.size.width - 48.0);

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
            child: AnimatedBuilder(
              animation: _fade,
              builder: (BuildContext context, Widget? child) {
                // Gentle 10px rise on the way in; stays put while holding.
                final double lift = 10 * (1 - _fade.value);
                return Transform.translate(
                  offset: Offset(0, lift),
                  child: child,
                );
              },
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xF02A2D3A),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
