import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// Wraps [child] with a swipe-to-reveal delete action (redesign v11 §4
/// `SwipeToDelete`): dragging left past [threshold] (dp) reveals a red
/// "Excluir" button; tapping it collapses the row and calls [onDelete].
///
/// A "Excluir" custom semantics action mirrors the gesture for a
/// screen-reader or switch-control user, who cannot drag a list row (redesign
/// v11 §8). [onUndo], when given, is offered as a "Desfazer" action on the
/// snackbar this widget shows right after deleting — restoring the
/// underlying data is the caller's job; this widget only asks for it.
///
/// There is no caller yet: the history screen still renders a thumbnail grid
/// (redesign v11 PR 10 wires this in).
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
    this.onUndo,
    this.threshold = 50,
  });

  final Widget child;
  final VoidCallback onDelete;
  final VoidCallback? onUndo;

  /// Drag distance (dp) past which the delete action is considered revealed.
  final double threshold;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  static const double _actionWidth = 104;

  double _dragExtent = 0;
  bool _revealed = false;
  bool _dragging = false;
  bool _exiting = false;

  void _onDragStart(DragStartDetails details) {
    if (_exiting) return;
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_exiting) return;
    setState(() {
      _dragExtent = (_dragExtent - details.delta.dx).clamp(0, _actionWidth);
    });
    if (_dragExtent >= widget.threshold && !_revealed) {
      _revealed = true;
      AppHaptics.selection();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_exiting) return;
    setState(() {
      _dragging = false;
      if (_dragExtent >= widget.threshold) {
        _dragExtent = _actionWidth;
        _revealed = true;
      } else {
        _dragExtent = 0;
        _revealed = false;
      }
    });
  }

  void _close() {
    if (!_revealed) return;
    setState(() {
      _dragExtent = 0;
      _revealed = false;
    });
  }

  Future<void> _delete() async {
    if (_exiting) return;
    setState(() {
      _exiting = true;
      _dragExtent = _actionWidth;
    });
    await AppHaptics.result();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    widget.onDelete();
    messenger?.showSnackBar(SnackBar(
      content: const Text('Análise excluída'),
      action: widget.onUndo == null
          ? null
          : SnackBarAction(
              label: 'Desfazer',
              onPressed: () {
                AppHaptics.confirm();
                widget.onUndo!();
              },
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final transform = Matrix4.translationValues(-_dragExtent, 0, 0);

    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Excluir'): _delete,
      },
      child: ClipRect(
        child: AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.base),
          curve: AppMotion.emphasized,
          alignment: Alignment.topCenter,
          child: _exiting
              ? const SizedBox(height: 0, width: double.infinity)
              : GestureDetector(
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      if (_dragExtent > 0)
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: _actionWidth,
                              child: Material(
                                color: palette.destructive,
                                child: Semantics(
                                  button: true,
                                  label: 'Excluir',
                                  child: InkWell(
                                    onTap: _delete,
                                    child: const Center(
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.delete_outline,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              SizedBox(width: AppSpacing.xs),
                                              Text(
                                                'Excluir',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      AnimatedContainer(
                        duration: _dragging
                            ? Duration.zero
                            : AppMotion.durationOf(context, AppMotion.fast),
                        curve: AppMotion.standard,
                        transform: transform,
                        child: GestureDetector(
                          onTap: _revealed ? _close : null,
                          child: widget.child,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
