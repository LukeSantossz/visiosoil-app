import 'package:flutter/material.dart';

/// Indicador de loading padronizado do VisioSoil.
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({
    super.key,
    this.size = 40.0,
    this.strokeWidth = 3.0,
    this.color,
  });

  /// Tamanho do indicador. Padrão: 40.
  final double size;

  /// Espessura do traço. Padrão: 3.
  final double strokeWidth;

  /// Cor do indicador. Usa primary se não especificado.
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
