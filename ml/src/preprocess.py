"""Image preprocessing and augmentation for the soil classifier pipeline."""

import tensorflow as tf


def normalize_imagenet(image: tf.Tensor, mean: list[float], std: list[float]) -> tf.Tensor:
    """Apply ImageNet normalization: (pixel/255 - mean) / std.

    Args:
        image: Tensor of shape (H, W, 3), dtype uint8 or float32.
        mean: Per-channel mean [R, G, B].
        std: Per-channel std [R, G, B].

    Returns:
        Normalized float32 tensor.
    """
    image = tf.cast(image, tf.float32) / 255.0
    mean_t = tf.constant(mean, dtype=tf.float32)
    std_t = tf.constant(std, dtype=tf.float32)
    return (image - mean_t) / std_t


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
    mean = cfg["preprocessing"]["mean"]
    std = cfg["preprocessing"]["std"]

    image = resize(image, size)
    image = normalize_imagenet(image, mean, std)
    return image


def build_augmentation_layer(cfg: dict) -> tf.keras.Sequential:
    """Build a Keras augmentation pipeline from config.

    Args:
        cfg: Configuration dictionary with augmentation section.

    Returns:
        Sequential model with augmentation layers.
    """
    aug_cfg = cfg.get("augmentation", {})
    layers = []

    if aug_cfg.get("horizontal_flip", False):
        layers.append(tf.keras.layers.RandomFlip("horizontal"))

    rotation = aug_cfg.get("rotation_range", 0)
    if rotation > 0:
        layers.append(tf.keras.layers.RandomRotation(rotation / 360.0))

    brightness = aug_cfg.get("brightness_range")
    if brightness:
        factor = brightness[1] - 1.0
        layers.append(tf.keras.layers.RandomBrightness(factor=factor))

    zoom = aug_cfg.get("zoom_range")
    if zoom:
        zoom_factor = 1.0 - zoom[0]
        layers.append(tf.keras.layers.RandomZoom(height_factor=(-zoom_factor, zoom_factor)))

    return tf.keras.Sequential(layers, name="augmentation")
