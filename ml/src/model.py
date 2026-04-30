"""Model architecture: SqueezeNet (custom Keras) with Dense classification head.

SqueezeNet implementation based on Iandola et al. 2016.
Fallback to MobileNetV2 (tf.keras.applications) via config.model.architecture.
"""

import tensorflow as tf
from tensorflow import keras


def _fire_module(x: tf.Tensor, squeeze: int, expand: int, name: str) -> tf.Tensor:
    """SqueezeNet fire module: squeeze 1x1 -> expand 1x1 + expand 3x3 -> concat.

    Args:
        x: Input tensor.
        squeeze: Number of filters in squeeze layer.
        expand: Number of filters in each expand branch.
        name: Module name prefix.

    Returns:
        Concatenated output tensor.
    """
    sq = keras.layers.Conv2D(squeeze, (1, 1), activation="relu", padding="same", name=f"{name}_sq")(x)
    ex1 = keras.layers.Conv2D(expand, (1, 1), activation="relu", padding="same", name=f"{name}_ex1")(sq)
    ex3 = keras.layers.Conv2D(expand, (3, 3), activation="relu", padding="same", name=f"{name}_ex3")(sq)
    return keras.layers.Concatenate(name=f"{name}_concat")([ex1, ex3])


def _build_squeezenet_backbone(input_tensor: tf.Tensor) -> tf.Tensor:
    """Build SqueezeNet 1.1 backbone (feature extractor only, no classification head).

    Architecture follows SqueezeNet 1.1 with reduced computation:
    - Conv1 -> MaxPool -> Fire2-3 -> MaxPool -> Fire4-5 -> MaxPool -> Fire6-7-8-9

    Args:
        input_tensor: Input tensor of shape (batch, 224, 224, 3).

    Returns:
        Feature tensor before global average pooling.
    """
    x = keras.layers.Conv2D(64, (3, 3), strides=2, activation="relu", padding="same", name="conv1")(input_tensor)
    x = keras.layers.MaxPooling2D((3, 3), strides=2, padding="same", name="pool1")(x)

    x = _fire_module(x, squeeze=16, expand=64, name="fire2")
    x = _fire_module(x, squeeze=16, expand=64, name="fire3")
    x = keras.layers.MaxPooling2D((3, 3), strides=2, padding="same", name="pool3")(x)

    x = _fire_module(x, squeeze=32, expand=128, name="fire4")
    x = _fire_module(x, squeeze=32, expand=128, name="fire5")
    x = keras.layers.MaxPooling2D((3, 3), strides=2, padding="same", name="pool5")(x)

    x = _fire_module(x, squeeze=48, expand=192, name="fire6")
    x = _fire_module(x, squeeze=48, expand=192, name="fire7")
    x = _fire_module(x, squeeze=64, expand=256, name="fire8")
    x = _fire_module(x, squeeze=64, expand=256, name="fire9")

    return x


def build_model(cfg: dict) -> keras.Model:
    """Build the classification model based on config.

    Supports:
    - "squeezenet": Custom SqueezeNet 1.1 implementation (no pretrained weights).
    - "mobilenetv2": tf.keras.applications.MobileNetV2 with ImageNet weights.

    Args:
        cfg: Configuration dictionary.

    Returns:
        Compiled Keras Model with softmax output.
    """
    num_classes = len(cfg["classes"])
    image_size = cfg["data"]["image_size"]
    architecture = cfg["model"]["architecture"]
    dropout = cfg["model"]["dropout"]
    learning_rate = cfg["training"]["learning_rate"]

    input_shape = (image_size, image_size, 3)
    inputs = keras.Input(shape=input_shape, name="input_image")

    if architecture == "squeezenet":
        features = _build_squeezenet_backbone(inputs)
    elif architecture == "mobilenetv2":
        backbone = keras.applications.MobileNetV2(
            input_shape=input_shape,
            include_top=False,
            weights="imagenet",
        )
        freeze = cfg["model"].get("freeze_backbone", True)
        backbone.trainable = not freeze
        features = backbone(inputs)
    else:
        raise ValueError(f"Unknown architecture: {architecture}")

    x = keras.layers.GlobalAveragePooling2D(name="gap")(features)
    x = keras.layers.Dropout(dropout, name="dropout")(x)
    outputs = keras.layers.Dense(num_classes, activation="softmax", name="predictions")(x)

    model = keras.Model(inputs=inputs, outputs=outputs, name=f"soil_{architecture}")

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=learning_rate),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )

    return model
