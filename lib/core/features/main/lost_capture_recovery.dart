import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/services/lost_capture_service.dart';
import 'package:visiosoil_app/providers/lost_capture_service_provider.dart';

/// Asks once, when home first appears, whether Android killed the app during a
/// capture (SPEC 0096). A recovered photograph opens the capture screen with
/// it; a capture that could not be recovered is reported with a snackbar.
///
/// Lives around home rather than in the splash, so it runs however the app
/// arrives there, after the splash or after onboarding.
class LostCaptureRecovery extends ConsumerStatefulWidget {
  const LostCaptureRecovery({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LostCaptureRecovery> createState() =>
      _LostCaptureRecoveryState();
}

class _LostCaptureRecoveryState extends ConsumerState<LostCaptureRecovery> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recover());
  }

  Future<void> _recover() async {
    final LostCapture lost;
    try {
      lost = await ref.read(lostCaptureServiceProvider).retrieve();
    } catch (e) {
      // Nothing to show the user: the check found no photograph to offer.
      developer.log('Lost capture check failed: $e',
          name: 'LostCaptureRecovery');
      return;
    }
    if (!mounted) return;
    switch (lost) {
      case NoLostCapture():
        return;
      case RecoveredCapture(:final path):
        context.push('/capture', extra: path);
      case UnrecoverableCapture():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.lostCaptureUnrecoverable)),
        );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
