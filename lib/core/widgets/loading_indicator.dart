import 'package:flutter/material.dart';

/// Standardized VisioSoil loading indicator.
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({
    super.key,
    this.size = 40.0,
    this.strokeWidth = 3.0,
    this.color,
  });

  /// Indicator size. Default: 40.
  final double size;

  /// Stroke width. Default: 3.
  final double strokeWidth;

  /// Indicator color. Uses primary if not specified.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          valueColor: color != null
              ? AlwaysStoppedAnimation<Color>(color!)
              : null,
        ),
      ),
    );
  }
}
