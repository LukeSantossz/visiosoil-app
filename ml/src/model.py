"""Model architecture: MobileNetV2 (transfer learning) with Dense classification head.

Uses MobileNetV2 pretrained on ImageNet as feature extractor.
Rescaling layer baked into the model converts [0,1] input to [-1,1].
"""

import tensorflow as tf
from tensorflow import keras


def build_model(cfg: dict) -> keras.Model:
    """Build the MobileNetV2-based classification model.

    Architecture:
        Input [1, 224, 224, 3] float32 in [0, 1]
        -> Rescaling(2.0, offset=-1.0)  # converts [0,1] -> [-1,1]
        -> MobileNetV2 backbone (ImageNet weights, no top)
        -> GlobalAveragePooling2D
        -> BatchNormalization
        -> Dense(256, relu)
        -> Dropout(0.5)
        -> Dense(num_classes, softmax)

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

    if architecture != "mobilenetv2":
        raise ValueError(f"Unknown architecture: {architecture}")

    input_shape = (image_size, image_size, 3)
    inputs = keras.Input(shape=input_shape, name="input_image")

    # Rescaling baked into model: [0,1] -> [-1,1] (MobileNetV2 expects [-1,1])
    x = keras.layers.Rescaling(scale=2.0, offset=-1.0, name="rescaling")(inputs)

    # MobileNetV2 backbone
    backbone = keras.applications.MobileNetV2(
        input_shape=input_shape,
        include_top=False,
        weights="imagenet",
    )
    freeze = cfg["model"].get("freeze_backbone", True)
    backbone.trainable = not freeze
    x = backbone(x)

    # Classification head
    x = keras.layers.GlobalAveragePooling2D(name="gap")(x)
    x = keras.layers.BatchNormalization(name="bn")(x)
    x = keras.layers.Dense(256, activation="relu", name="dense_head")(x)
    x = keras.layers.Dropout(dropout, name="dropout")(x)
    outputs = keras.layers.Dense(num_classes, activation="softmax", name="predictions")(x)

    model = keras.Model(inputs=inputs, outputs=outputs, name="soil_mobilenetv2")

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=learning_rate),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )

    return model


def unfreeze_model(model: keras.Model, cfg: dict) -> keras.Model:
    """Unfreeze the top N layers of the backbone for fine-tuning.

    Recompiles the model with a lower learning rate.

    Args:
        model: Compiled Keras model (from build_model).
        cfg: Configuration dictionary.

    Returns:
        Recompiled model with partially unfrozen backbone.
    """
    unfreeze_layers = cfg["model"].get("unfreeze_layers", 50)
    fine_tune_lr = cfg["training"].get("fine_tune_learning_rate", 1e-5)

    # Find the MobileNetV2 backbone by name pattern
    backbone = None
    for layer in model.layers:
        if hasattr(layer, "layers") and "mobilenetv2" in layer.name.lower():
            backbone = layer
            break

    if backbone is None:
        raise RuntimeError("Could not find MobileNetV2 backbone in model")

    # Unfreeze the backbone
    backbone.trainable = True

    # Freeze all layers except the last `unfreeze_layers`
    for layer in backbone.layers[:-unfreeze_layers]:
        layer.trainable = False

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=fine_tune_lr),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )

    return model
