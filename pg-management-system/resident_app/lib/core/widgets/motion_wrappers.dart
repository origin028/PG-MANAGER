import 'package:flutter/material.dart';

/// Bounded, reduced-motion-aware entrance transition applying fade and slight slide-up
/// around existing widgets without changing their layout, size, or styling.
class MotionEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset slideOffset;

  const MotionEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 360),
    this.slideOffset = const Offset(0, 0.03),
  });

  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;
  late final Animation<Offset> _slide;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final totalMs =
        (widget.delay.inMilliseconds + widget.duration.inMilliseconds)
            .clamp(1, 3000);
    final beginFraction =
        (widget.delay.inMilliseconds / totalMs).clamp(0.0, 0.92);

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(beginFraction, 1.0, curve: Curves.easeOutCubic),
    );
    _slide = Tween<Offset>(
      begin: widget.slideOffset,
      end: Offset.zero,
    ).animate(_curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnim) {
        _controller.value = 1.0;
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) return widget.child;

    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

/// Non-intrusive pointer press feedback wrapper using Listener so it never
/// competes in the gesture arena with wrapped buttons, InkWells, or links.
class TactilePress extends StatefulWidget {
  final Widget child;
  final double scaleDown;
  final Duration duration;

  const TactilePress({
    super.key,
    required this.child,
    this.scaleDown = 0.975,
    this.duration = const Duration(milliseconds: 110),
  });

  @override
  State<TactilePress> createState() => _TactilePressState();
}

class _TactilePressState extends State<TactilePress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: (_pressed && !disableAnim) ? widget.scaleDown : 1.0,
        duration: disableAnim ? Duration.zero : widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

