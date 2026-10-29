/// Static reference text for each class the model emits, keyed by the
/// contract's class name (redesign v11 §3.6, SPEC 0194). It describes the
/// SiBCS (Embrapa) textural group the class names, never the sample: the
/// model returns no fractions (redesign v11 §11). Like `SoilTextureColors`,
/// it is not model output and degrades for a label it does not know, which is
/// why the texture class literal guard permits this file. Pending an
/// agronomist's review.
abstract final class SoilTextureReference {
  /// The classes the model classifies, by contract name and in texture order,
  /// which are the classes a correction may record as a sample's true class
  /// (SPEC 0220). Siltosa is not among them (ADR 0016).
  static const List<String> modelClasses = [
    'Arenosa',
    'Media',
    'Argilosa',
    'Muito Argilosa',
  ];

  static const Map<String, String> _about = {
    'Arenosa': 'Solos de textura arenosa têm menos de 15% de argila e mais '
        'de 70% de areia, segundo o SiBCS (Embrapa). Drenam rápido, retêm '
        'pouca água e poucos nutrientes e sofrem erosão com facilidade.',
    'Media': 'Solos de textura média têm menos de 35% de argila e mais de '
        '15% de areia, fora das classes areia e areia franca, segundo o '
        'SiBCS (Embrapa). Equilibram drenagem e retenção de água e costumam '
        'ser de manejo mais fácil.',
    'Argilosa': 'Solos de textura argilosa têm entre 35% e 60% de argila, '
        'segundo o SiBCS (Embrapa). Retêm bem água e nutrientes e compactam '
        'com facilidade quando úmidos.',
    'Muito Argilosa': 'Solos de textura muito argilosa têm mais de 60% de '
        'argila, segundo o SiBCS (Embrapa). Retêm muita água e nutrientes, '
        'ficam pegajosos quando molhados e compactam com facilidade.',
  };

  /// The reference text for [textureClass], or null for a class without one.
  static String? forClass(String? textureClass) => _about[textureClass];

  /// The contract names whose display label differs from the name: pt-BR
  /// copy needs the accent and sentence case (SPEC 0195).
  static const Map<String, String> _labels = {
    'Media': 'Média',
    'Muito Argilosa': 'Muito argilosa',
  };

  /// How [textureClass] reads on screen and in shared text. Stored and sent
  /// values keep the contract's name; a name without a label reads as is.
  static String labelFor(String textureClass) =>
      _labels[textureClass] ?? textureClass;
}
