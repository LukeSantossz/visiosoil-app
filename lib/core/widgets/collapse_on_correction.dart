import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';

/// Collapses its child when [isError] goes from true to false.
///
/// The corrected child is built on that frame. Any other swap, including an
/// error appearing, changes size in no time. Reduced motion does too
/// (SPEC 0138).
class CollapseOnCorrection extends StatefulWidget {
  const CollapseOnCorrection({
    super.key,
    required this.isError,
    required this.child,
  });

  final bool isError;
  final Widget child;

  @override
  State<CollapseOnCorrection> createState() => _CollapseOnCorrectionState();
}

class _CollapseOnCorrectionState extends State<CollapseOnCorrection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CollapseOnCorrection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (oldWidget.isError && !widget.isError && !reduce) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CollapseBox(
      animation: _controller,
      curve: AppMotion.standard,
      child: widget.child,
    );
  }
}

class _CollapseBox extends SingleChildRenderObjectWidget {
  const _CollapseBox({
    required this.animation,
    required this.curve,
    required super.child,
  });

  final Animation<double> animation;
  final Curve curve;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCollapse(animation: animation, curve: curve);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderCollapse renderObject) {
    renderObject
      ..animation = animation
      ..curve = curve;
  }
}

class _RenderCollapse extends RenderShiftedBox {
  _RenderCollapse({
    required this._animation,
    required this._curve,
  }) : super(null) {
    _animation.addListener(_tick);
  }

  Animation<double> _animation;
  Curve _curve;
  Size? _from;

  Animation<double> get animation => _animation;

  set animation(Animation<double> value) {
    if (value == _animation) return;
    _animation.removeListener(_tick);
    _animation = value;
    _animation.addListener(_tick);
  }

  set curve(Curve value) => _curve = value;

  void _tick() => markNeedsLayout();

  @override
  void dispose() {
    _animation.removeListener(_tick);
    super.dispose();
  }

  @override
  void performLayout() {
    final box = child!;
    box.layout(constraints.loosen(), parentUsesSize: true);
    final target = box.size;
    if (_animation.isAnimating && hasSize) {
      _from ??= size;
      final t = _curve.transform(_animation.value);
      size = Size.lerp(_from, target, t)!;
    } else {
      _from = null;
      size = target;
    }
    (box.parentData! as BoxParentData).offset = Offset.zero;
  }
}
