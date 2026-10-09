import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// Two Soil Records side by side, read-only, the older on the left
/// (SPEC 0150).
class CompareScreen extends ConsumerWidget {
  const CompareScreen({
    super.key,
    required this.firstId,
    required this.secondId,
  });

  final int firstId;
  final int secondId;

  static const _title = 'Comparar registros';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = ref.watch(soilRecordByIdProvider(firstId));
    final second = ref.watch(soilRecordByIdProvider(secondId));

    // Loading first: a retry reloads while the previous error is still held.
    if (first.isLoading || second.isLoading) {
      return const Scaffold(body: LoadingIndicator());
    }
    if (first.hasError || second.hasError) {
      return Scaffold(
        appBar: const VisioAppBar(title: _title),
        body: ErrorState(
          message: 'Não foi possível carregar os registros.',
          onRetry: () {
            ref.invalidate(soilRecordByIdProvider(firstId));
            ref.invalidate(soilRecordByIdProvider(secondId));
          },
        ),
      );
    }
    final a = first.value;
    final b = second.value;
    if (a == null || b == null) {
      // The shared error state, with nothing to retry (SPEC 0124).
      return const Scaffold(
        appBar: VisioAppBar(title: _title),
        body: ErrorState(message: 'Registro não encontrado'),
      );
    }

    final pair = [a, b]..sort((x, y) => _instant(x).compareTo(_instant(y)));
    return Scaffold(
      appBar: const VisioAppBar(title: _title),
      body: SafeArea(
        top: false,
        child: _Comparison(older: pair[0], newer: pair[1]),
      ),
    );
  }

  static DateTime _instant(SoilRecord record) =>
      DateTime.tryParse(record.timestamp) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.older, required this.newer});

  final SoilRecord older;
  final SoilRecord newer;

  @override
  Widget build(BuildContext context) {
    // A short, fixed page: built whole rather than lazily.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SideBySide(
            left: _Photograph(record: older),
            right: _Photograph(record: newer),
          ),
          const SizedBox(height: AppSpacing.md),
          _SideBySide(
            left: _Identity(record: older),
            right: _Identity(record: newer),
          ),
          const SizedBox(height: AppSpacing.md),
          _ValueRow(
            caption: 'Classe textural',
            left: _Texture(record: older),
            right: _Texture(record: newer),
          ),
          _ValueRow(
            caption: 'Confiança',
            left: _Value(older.formattedConfidence),
            right: _Value(newer.formattedConfidence),
          ),
          _ValueRow(
            caption: 'Data da coleta',
            left: _Value(older.formattedTimestamp),
            right: _Value(newer.formattedTimestamp),
          ),
          _ValueRow(
            caption: 'Localização',
            left: _Location(record: older),
            right: _Location(record: newer),
          ),
        ],
      ),
    );
  }
}

/// Half the width each, so a value is read across from its counterpart.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: right),
      ],
    );
  }
}

/// A caption across the full width, then both records' values.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.caption,
    required this.left,
    required this.right,
  });

  final String caption;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: AppSpacing.xl),
        Text(
          caption,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.palette.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _SideBySide(left: left, right: right),
      ],
    );
  }
}

class _Photograph extends StatelessWidget {
  const _Photograph({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).width / 2;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    // Not a button: the comparison only reads (SPEC 0150). The identity
    // below names the record, so the photograph says nothing more.
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: AppRadius.borderRadiusMd,
        child: Image.file(
          File(record.imagePath),
          fit: BoxFit.cover,
          cacheWidth: (side * dpr).round(),
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => Container(
            color: context.palette.surfaceVariant,
            child: Center(
              child: Icon(
                Icons.broken_image,
                size: 32,
                color: context.palette.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    return Text(
      record.hasLabels ? record.labelsSummary : 'Sem identificação',
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}

class _Texture extends StatelessWidget {
  const _Texture({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final color = record.hasClassification
        ? SoilTextureColors.forClass(record.textureClass!)
        : context.palette.outline;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: _Value(record.displayTextureClass)),
      ],
    );
  }
}

class _Location extends StatelessWidget {
  const _Location({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Value(
          record.hasValidAddress
              ? record.displayAddress
              : 'Endereço indisponível',
        ),
        if (record.hasCoordinates)
          Text(
            record.formattedCoordinates,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.palette.onSurfaceVariant,
                ),
          ),
      ],
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodyMedium);
  }
}
