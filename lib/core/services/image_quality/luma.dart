/// ITU-R BT.601 luma, declared once for every path that turns colour into grey:
/// the quality analyzer (SPEC 0030) and the patch grid (SPEC 0081).
///
/// `ml/src/image_quality.py` declares the same three coefficients, and SPEC
/// 0037 requires the model path and the analyzer to read one definition, so a
/// test asserts no other file under `lib/` declares them.
library;

const double lumaRed = 0.299;
const double lumaGreen = 0.587;
const double lumaBlue = 0.114;
