import 'package:flutter/widgets.dart';
import 'package:visiosoil_app/core/theme/app_layout.dart';

/// Caps [child] at [AppLayout.maxContentWidth] and centres it horizontally
/// (SPEC 0265).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
        child: child,
      ),
    );
  }
}

/// Centres [child] in the space it is given, and scrolls it when it does not
/// fit, as on a short screen or at large text (SPEC 0265). Inside a scrolling
/// parent, whose height is unbounded, it only pads and centres.
class CentredScroll extends StatelessWidget {
  const CentredScroll({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final capped = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
      child: child,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return Padding(
            padding: padding,
            child: Center(child: capped),
          );
        }
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - padding.vertical).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Center(child: capped),
          ),
        );
      },
    );
  }
}

/// Whether the text is scaled for large text (SPEC 0121).
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= AppLayout.largeTextScale;

/// Whether the screen is short, as every phone in landscape is.
bool isShortScreen(BuildContext context) =>
    MediaQuery.sizeOf(context).height < AppLayout.shortHeight;
