import 'package:flutter/material.dart';

/// One point of the capture protocol: its icon, its title and its sentence.
class CaptureProtocolStep {
  const CaptureProtocolStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// The capture protocol the A4-sheet reader assumes, one point per step
/// (ADR 0017, SPEC 0104). The onboarding and the capture guide both read it,
/// so the guide can never teach a protocol the onboarding does not
/// (SPEC 0142). A photograph taken any other way is refused by name.
const captureProtocolSteps = <CaptureProtocolStep>[
  CaptureProtocolStep(
    icon: Icons.description_outlined,
    title: 'Folha A4',
    description:
        'Use uma folha A4 branca, sem nada escrito, sobre uma superfície '
        'mais escura que o papel. Não coloque mais nada sobre ela.',
  ),
  CaptureProtocolStep(
    icon: Icons.blur_circular,
    title: 'Amostra',
    description: 'Espalhe o solo em um círculo de 8 a 10 cm no meio da folha.',
  ),
  CaptureProtocolStep(
    icon: Icons.photo_camera_outlined,
    title: 'Foto',
    description:
        'Fotografe de cima, com a folha inteira no quadro e uma margem em '
        'volta, em luz difusa e sem flash.',
  ),
];
