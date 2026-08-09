"""Image preprocessing and augmentation for the soil classifier pipeline."""

import tensorflow as tf


def normalize_mobilenet_v2(image: tf.Tensor) -> tf.Tensor:
    """Normalize for MobileNetV2 with baked-in Rescaling layer.

    The model always contains a Rescaling(2.0, -1.0) layer that converts [0,1]
    to [-1,1], so the preprocessing only divides by 255. There is no other case:
    `bake_into_model: false` is rejected by `load_config`.

    Args:
        image: Tensor of shape (H, W, 3), dtype uint8 or float32.

    Returns:
        Float32 tensor in [0, 1] range.
    """
    return tf.cast(image, tf.float32) / 255.0


def resize(image: tf.Tensor, size: int) -> tf.Tensor:
    """Resize image to (size, size) using bilinear interpolation.

    Args:
        image: Tensor of shape (H, W, 3).
        size: Target height and width.

    Returns:
        Resized tensor of shape (size, size, 3).
    """
    return tf.image.resize(image, [size, size])


def preprocess(image: tf.Tensor, cfg: dict) -> tf.Tensor:
    """Full preprocessing pipeline: resize + normalize.

    Args:
        image: Raw image tensor (H, W, 3), uint8.
        cfg: Configuration dictionary with data.image_size and preprocessing.

    Returns:
        Preprocessed float32 tensor (size, size, 3).
    """
    size = cfg["data"]["image_size"]
    normalization = cfg["preprocessing"]["normalization"]

    image = resize(image, size)

    if normalization == "mobilenet_v2":
        image = normalize_mobilenet_v2(image)
    else:
        raise ValueError(f"Unknown normalization: {normalization}")

    return image


def build_augmentation_layer(cfg: dict) -> tf.keras.Sequential:
    """Build a Keras augmentation pipeline from config.

    Args:
        cfg: Configuration dictionary with augmentation section.

    Returns:
        Sequential model with augmentation layers.
    """
    aug_cfg = cfg.get("augmentation", {})
    if not aug_cfg:
        return tf.keras.Sequential([], name="augmentation")

    # Every layer holds its own generator, so a global seed does not reach it.
    seed = cfg["data"]["seed"]
    layers = []

    if aug_cfg.get("horizontal_flip", False):
        layers.append(tf.keras.layers.RandomFlip("horizontal", seed=seed))

    if aug_cfg.get("vertical_flip", False):
        layers.append(tf.keras.layers.RandomFlip("vertical", seed=seed))

    rotation = aug_cfg.get("rotation_range", 0)
    if rotation > 0:
        layers.append(tf.keras.layers.RandomRotation(rotation / 360.0, seed=seed))

    brightness = aug_cfg.get("brightness_range")
    if brightness:
        # RandomBrightness adds a delta, so a multiplicative range [lo, hi]
        # maps to the offsets it spans. Both bounds are carried: taking only
        # hi - 1.0 would silently symmetrize an asymmetric range.
        layers.append(tf.keras.layers.RandomBrightness(
            factor=(brightness[0] - 1.0, brightness[1] - 1.0),
            value_range=(0.0, 1.0),
            seed=seed,
        ))

    contrast = aug_cfg.get("contrast_range")
    if contrast:
        # RandomContrast realizes [1 - min(factor), 1 + max(factor)] and, unlike
        # RandomBrightness, expands a float `f` to `(0, f)` rather than
        # `(-f, f)`. Passing the radius as a float therefore never reduces
        # contrast: the configured lower bound was silently discarded. The pair
        # must be given explicitly. It also means the two sides cannot be set
        # independently, since the tuple is sorted, so `load_config` rejects an
        # asymmetric range rather than let one be approximated.
        radius = contrast[1] - 1.0
        layers.append(tf.keras.layers.RandomContrast(
            factor=(radius, radius),
            value_range=(0.0, 1.0),
            seed=seed,
        ))

    zoom = aug_cfg.get("zoom_range")
    if zoom:
        zoom_lower = zoom[0] - 1.0  # e.g. 0.95 - 1.0 = -0.05 (zoom out)
        zoom_upper = zoom[1] - 1.0  # e.g. 1.05 - 1.0 = 0.05 (zoom in)
        layers.append(tf.keras.layers.RandomZoom(
            height_factor=(zoom_lower, zoom_upper), seed=seed,
        ))

    translation = aug_cfg.get("translation_range")
    if translation:
        layers.append(tf.keras.layers.RandomTranslation(
            height_factor=translation,
            width_factor=translation,
            seed=seed,
        ))

    return tf.keras.Sequential(layers, name="augmentation")
