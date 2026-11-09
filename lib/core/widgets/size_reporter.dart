import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lays out [child] as it is, and after each layout that changes its size
/// reports the new size to [onSize] once the frame is done, so a parent can
/// lay out around a child whose height depends on the text scale
/// (SPEC 0265).
class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({super.key, required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSizeReporter).onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size;
    if (measured == _reported) return;
    _reported = measured;
    SchedulerBinding.instance.addPostFrameCallback((_) => onSize(measured));
  }
}
