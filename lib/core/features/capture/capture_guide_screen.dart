import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/constants/capture_protocol.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/providers/capture_guide_store_provider.dart';

/// The capture protocol on a route of its own (SPEC 0142): shown before the
/// first camera launch, and on demand from capture and Settings.
///
/// Only the primary action marks the guide seen, and it returns `true`. Back
/// returns nothing, so a caller that would open the camera does not.
class CaptureGuideScreen extends ConsumerStatefulWidget {
  const CaptureGuideScreen({super.key, this.beforeCamera = false});

  /// Whether the camera opens once the guide is confirmed, which names the
  /// primary action. Opened on demand, the guide only returns to its caller,
  /// which may already hold a photograph.
  final bool beforeCamera;

  @override
  ConsumerState<CaptureGuideScreen> createState() => _CaptureGuideScreenState();
}

class _CaptureGuideScreenState extends ConsumerState<CaptureGuideScreen> {
  bool _isConfirming = false;

  Future<void> _confirm() async {
    // A second tap in the same frame would pop the caller as well.
    if (_isConfirming) return;
    // Back is held until the guide pops itself: a back taken during the write
    // would leave this pop to close the caller, and mark a guide the user left.
    setState(() => _isConfirming = true);

    try {
      await ref.read(captureGuideStoreProvider).markCaptureGuideSeen();
    } on Exception catch (e) {
      // A flag that cannot be written never keeps the camera closed; the
      // guide is shown again next time instead.
      developer.log(
        'Could not record the capture guide as seen: $e',
        name: 'CaptureGuideScreen',
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isConfirming,
      child: Scaffold(
        appBar: const VisioAppBar(title: 'Como capturar'),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Semantics(
                    label: '${captureProtocolSteps.length} passos',
                    container: true,
                    explicitChildNodes: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, step)
                            in captureProtocolSteps.indexed) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.lg),
                          _GuideStep(number: i + 1, step: step),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Pinned below the steps, so it stays in reach at any text size.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: VisioButton(
                  label: widget.beforeCamera ? 'Abrir câmera' : 'Entendi',
                  icon: widget.beforeCamera ? Icons.camera_alt : Icons.check,
                  onPressed: _confirm,
                  expanded: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One protocol step, read as a single node: its number, title and sentence.
/// The icon is decorative, since the text says everything it shows.
class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.number, required this.step});

  static const double _iconSize = 32;

  final int number;
  final CaptureProtocolStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(step.icon, size: _iconSize, color: palette.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$number. ${step.title}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  step.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
