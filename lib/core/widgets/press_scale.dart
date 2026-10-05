import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';

/// Shrinks the button it builds to [scale] while that button is pressed: the
/// design system's press feedback, over [AppMotion.instant] (SPEC 0134).
///
/// It follows the button's own pressed state, the one its ink follows, so a
/// disabled button never scales. Under reduced motion the scale changes in no
/// time.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.scale, required this.builder});

  /// The size while pressed, as a fraction of the button's own.
  final double scale;

  /// Builds the button, which must take [WidgetStatesController] as its
  /// `statesController`.
  final Widget Function(WidgetStatesController statesController) builder;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  final _states = WidgetStatesController();
  var _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_onStates);
  }

  void _onStates() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed == _pressed) return;
    // A button disabled mid-press clears its pressed state while it builds,
    // when this ancestor cannot be rebuilt; it then waits for the frame's end.
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (mounted) _onStates();
      });
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  void dispose() {
    _states
      ..removeListener(_onStates)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? widget.scale : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.instant,
      curve: AppMotion.standard,
      child: widget.builder(_states),
    );
  }
}
