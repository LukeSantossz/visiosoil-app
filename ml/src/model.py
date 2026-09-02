"""Model architecture: MobileNetV2 (transfer learning) with Dense classification head.

Uses MobileNetV2 pretrained on ImageNet as feature extractor.
Rescaling layer baked into the model converts [0,1] input to [-1,1].
"""

import math

from tensorflow import keras

from .config import OPTIONAL_MODEL_DEFAULTS


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
    # The default is declared in config.py, not invented here.
    freeze = cfg["model"].get("freeze_backbone", OPTIONAL_MODEL_DEFAULTS["freeze_backbone"])
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

    backbone = _find_backbone(model)

    # Unfreeze the backbone
    backbone.trainable = True

    # Freeze all layers except the last `unfreeze_layers`
    for layer in backbone.layers[:-unfreeze_layers]:
        layer.trainable = False

    # Return every BatchNormalization layer in the backbone to inference mode,
    # which is Keras' own remedy for a partially unfrozen pretrained backbone.
    # A trainable BatchNormalization layer runs in training mode during `fit`
    # and overwrites the ImageNet moving mean and variance with statistics
    # estimated from this dataset. Here that dataset is 221 photographs taken on
    # one rig, one device and one lighting condition
    # (`docs/ml/collection-protocol.md`), so the statistics it would learn
    # describe a single capture configuration rather than the population the
    # model is deployed against.
    #
    # Lowering `fine_tune_learning_rate` is not an alternative: the moving
    # statistics are updated by the forward pass, not by the optimizer, so no
    # learning rate governs them.
    #
    # The backbone only. `build_model` places a BatchNormalization layer in the
    # classification head, and that one was initialized on this dataset and has
    # no pretrained statistics to protect.
    for layer in backbone.layers:
        if isinstance(layer, keras.layers.BatchNormalization):
            layer.trainable = False

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=fine_tune_lr),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )

    return model


def _find_backbone(model: keras.Model) -> keras.Model:
    """The MobileNetV2 sub-model inside a model `build_model` produced."""
    for layer in model.layers:
        if hasattr(layer, "layers") and "mobilenetv2" in layer.name.lower():
            return layer
    raise RuntimeError("Could not find MobileNetV2 backbone in model")


def fine_tune_report(model: keras.Model) -> dict:
    """What unfreezing actually did to this model, for the fold's record.

    Every field is counted off the model rather than restated from the config.
    The config records the intent; this records the outcome, and the two are
    only the same while `unfreeze_model` is correct — which is the thing worth
    being able to see in an artifact rather than only in the code.

    `trainable_batch_norm_layers` is the one that carries a claim: it is zero
    whenever a fold trained under the fix above, and any other value in a stored
    artifact says that fold's backbone statistics were overwritten, whatever the
    code says today.

    `backbone_unfrozen` is False for a fold whose refit ran too few epochs to
    reach phase two, which is a real outcome of the nested epoch selection and
    not an error.
    """
    backbone = _find_backbone(model)
    batch_norms = [
        layer
        for layer in backbone.layers
        if isinstance(layer, keras.layers.BatchNormalization)
    ]
    # `math.prod` over the declared shape rather than a TensorFlow op: this
    # runs on a built model outside any graph, and a plain integer product
    # cannot fail on a variable type a future Keras changes.
    trainable_parameters = sum(
        math.prod(weight.shape) for weight in model.trainable_weights
    )
    return {
        "backbone_unfrozen": bool(backbone.trainable),
        "backbone_layers": len(backbone.layers),
        "trainable_backbone_layers": sum(
            1 for layer in backbone.layers if layer.trainable
        ),
        "batch_norm_layers": len(batch_norms),
        "trainable_batch_norm_layers": sum(
            1 for layer in batch_norms if layer.trainable
        ),
        "trainable_parameters": trainable_parameters,
        "non_trainable_parameters": int(model.count_params()) - trainable_parameters,
    }
