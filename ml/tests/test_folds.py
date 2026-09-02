"""Repeated stratified group k-fold generation and the fold manifest (SPEC 0042).

One test per acceptance criterion the fold layer owns, named after the criterion.
The three criteria the spec marks "over the real manifest" read
`ml/data/datasets/v1/`, which is git-ignored per ADR 0019 and therefore absent in
CI; they skip rather than fail there, and run wherever the archive is ingested.
"""

import json
from collections import Counter

import pytest

from src.dataset import (
    FOLD_MANIFEST_FILENAME,
    FOLD_SCHEMA_VERSION,
    REGENERATE_FOLDS_COMMAND,
    SEED_DERIVATION,
    create_folds,
    derive_repeat_seed,
    fold_split,
    inner_folds,
    library_versions,
    load_folds,
    permute_labels_by_group,
    rebalance_fold_assignment,
    selection_groups,
)
from src.manifest import (
    class_images,
    manifest_digest,
    read_manifest,
    sample_ids_by_image,
    train_only_sample_ids,
)
from tests.support import (
    CLASSES,
    configured_classes,
    real_manifest_or_skip,
    write_version,
)

K = 5
REPEATS = 5
SEED = 42


def generate(tmp_path, root, *, classes=CLASSES, k=K, repeats=REPEATS, seed=SEED,
             train_only=None, with_provenance=True):
    """Generate the fold manifest for the dataset version at ``root``."""
    manifest = read_manifest(root, classes)
    splits_dir = tmp_path / "splits"
    folds = create_folds(
        class_images(manifest, classes),
        k=k,
        repeats=repeats,
        seed=seed,
        splits_dir=str(splits_dir),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version if with_provenance else None,
        manifest_digest=manifest.digest if with_provenance else None,
        train_only_samples=train_only,
    )
    return manifest, splits_dir, folds


def real_folds(tmp_path, **kwargs):
    """Fold manifest over the ingested archive, or a skip when it is absent."""
    manifest = real_manifest_or_skip()
    folds = create_folds(
        class_images(manifest, configured_classes()),
        k=K,
        repeats=REPEATS,
        seed=SEED,
        splits_dir=str(tmp_path / "splits"),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
        train_only_samples=train_only_sample_ids(manifest),
        **kwargs,
    )
    return manifest, folds


def splittable_assignments(folds, repeat):
    """Group id to fold index for the groups repeat ``repeat`` can test."""
    return {
        group_id: index
        for group_id, index in folds["folds"][str(repeat)].items()
        if index is not None
    }


# --- folds_are_stratified_and_group_aware ----------------------------------


def test_folds_are_stratified_and_group_aware(tmp_path):
    """Every splittable group gets exactly one fold index, class-balanced.

    "Within one group" is the tolerance the spec names: a class of 16 over five
    folds cannot be split evenly, so three or four is the honest requirement.
    """
    _, folds = real_folds(tmp_path)

    pooled = Counter(
        folds["groups"][group_id]["class"]
        for group_id in splittable_assignments(folds, 0)
    )
    assert sum(pooled.values()) == 77, "SPEC 0040 D6 measured 77 splittable groups"

    for repeat in range(REPEATS):
        assignments = splittable_assignments(folds, repeat)
        assert len(assignments) == sum(pooled.values())
        assert set(assignments.values()) == set(range(K))

        for fold in range(K):
            held = Counter(
                folds["groups"][group_id]["class"]
                for group_id, index in assignments.items()
                if index == fold
            )
            for texture_class, total in pooled.items():
                assert abs(held[texture_class] - total / K) <= 1, (
                    f"repeat {repeat} fold {fold} holds {held[texture_class]} "
                    f"{texture_class} groups against {total / K:.2f} expected"
                )


def test_every_photograph_of_one_group_shares_its_fold(tmp_path):
    """Group-aware is asserted at the photograph level, where leakage happens."""
    root = write_version(tmp_path, extra_photographs=1)
    _, _, folds = generate(tmp_path, root)

    split = fold_split(folds, repeat=0, fold=0)
    for side in ("train", "test"):
        by_group = {}
        for entry in split[side]:
            by_group.setdefault(entry["group"], set()).add(entry["path"])
        assert by_group, f"{side} side is empty"

    test_groups = {entry["group"] for entry in split["test"]}
    train_groups = {entry["group"] for entry in split["train"]}
    assert not (test_groups & train_groups)


# --- every_group_is_tested_exactly_once_per_repeat --------------------------


def test_every_group_is_tested_exactly_once_per_repeat(tmp_path):
    root = write_version(tmp_path)
    _, _, folds = generate(tmp_path, root)

    splittable = set(splittable_assignments(folds, 0))
    for repeat in range(REPEATS):
        seen = Counter()
        for fold in range(K):
            for entry in fold_split(folds, repeat, fold)["test"]:
                seen[entry["group"]] += 1
        assert set(seen) == splittable
        tested_once = {
            group_id
            for group_id in splittable
            if seen[group_id] == len(_photographs(folds, group_id))
        }
        assert tested_once == splittable, "a group reached two test sides"


def _photographs(folds, group_id):
    return folds["groups"][group_id]["images"]


# --- train_only_groups_never_reach_a_test_side ------------------------------


def test_train_only_groups_never_reach_a_test_side(tmp_path):
    """The transported population trains and is never scored (SPEC 0040 D6)."""
    manifest, folds = real_folds(tmp_path)

    restricted = train_only_sample_ids(manifest)
    assert len(restricted) == 25, "SPEC 0040 D6 measured 25 train-only groups"

    train_only_groups = {
        group_id
        for group_id, record in folds["groups"].items()
        if record["train_only"]
    }
    assert train_only_groups

    for repeat in range(REPEATS):
        assert all(
            folds["folds"][str(repeat)][group_id] is None
            for group_id in train_only_groups
        )
        for fold in range(K):
            split = fold_split(folds, repeat, fold)
            assert not ({e["group"] for e in split["test"]} & train_only_groups)
            assert train_only_groups <= {e["group"] for e in split["train"]}


# --- class_below_k_groups_is_refused ----------------------------------------


def test_class_below_k_groups_is_refused(tmp_path):
    """The floor is k, not the three a three-way split needed."""
    root = write_version(tmp_path, samples_per_class=4)

    with pytest.raises(ValueError) as raised:
        generate(tmp_path, root, k=5)

    message = str(raised.value)
    assert "Arenosa" in message
    assert "4" in message
    assert "5" in message


def test_a_class_restricted_to_training_is_refused_by_name(tmp_path):
    """A class whose every group is train-only has no splittable group at all."""
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    doomed = {row.sample_id for row in manifest.rows if row.texture_class == "Media"}

    with pytest.raises(ValueError, match="Media"):
        generate(tmp_path, root, train_only=doomed)


# --- fold_manifest_records_provenance_and_fold_index ------------------------


def test_fold_manifest_records_provenance_and_fold_index(tmp_path):
    root = write_version(tmp_path)
    manifest, splits_dir, _ = generate(tmp_path, root)

    written = json.loads(
        (splits_dir / FOLD_MANIFEST_FILENAME).read_text(encoding="utf-8")
    )

    assert written["schema_version"] == FOLD_SCHEMA_VERSION
    assert written["dataset_version"] == manifest.version == "v1"
    assert written["manifest_digest"] == manifest_digest(root)
    assert written["classes"] == CLASSES
    assert written["k"] == K
    assert written["repeats"] == REPEATS
    assert written["seed"] == SEED
    assert written["seed_derivation"] == SEED_DERIVATION
    assert written["seeds"] == {
        str(repeat): derive_repeat_seed(SEED, repeat) for repeat in range(REPEATS)
    }
    assert written["train_only_samples"] == []

    every_group = set(written["groups"])
    for repeat in range(REPEATS):
        assert set(written["folds"][str(repeat)]) == every_group


def test_fold_manifest_records_the_train_only_samples_it_was_given(tmp_path):
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    restricted = {
        row.sample_id for row in manifest.rows if row.sample_id.endswith("-7")
    }

    _, splits_dir, _ = generate(tmp_path, root, train_only=restricted)

    written = json.loads(
        (splits_dir / FOLD_MANIFEST_FILENAME).read_text(encoding="utf-8")
    )
    assert written["train_only_samples"] == sorted(restricted)


# --- result_from_another_manifest_is_refused --------------------------------


def test_result_from_another_manifest_is_refused(tmp_path):
    root = write_version(tmp_path)
    manifest, splits_dir, _ = generate(tmp_path, root)

    with pytest.raises(ValueError) as raised:
        load_folds(str(splits_dir), manifest_digest="0" * 64)

    message = str(raised.value)
    assert manifest.digest in message
    assert "0" * 64 in message


def test_a_fold_manifest_that_belongs_to_the_dataset_loads(tmp_path):
    """The guard is a check, not a wall."""
    root = write_version(tmp_path)
    manifest, splits_dir, _ = generate(tmp_path, root)

    loaded = load_folds(str(splits_dir), manifest_digest=manifest.digest)

    assert loaded["dataset_version"] == "v1"


# --- stale_schema_is_refused ------------------------------------------------


def test_stale_schema_is_refused(tmp_path):
    """A SPEC 0033 splits.json must not be reinterpreted as a fold manifest."""
    splits_dir = tmp_path / "splits"
    splits_dir.mkdir()
    (splits_dir / FOLD_MANIFEST_FILENAME).write_text(
        json.dumps(
            {
                "seed": 42,
                "val_split": 0.15,
                "test_split": 0.15,
                "classes": CLASSES,
                "splits": {"train": [], "val": [], "test": []},
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError) as raised:
        load_folds(str(splits_dir))

    message = str(raised.value)
    assert REGENERATE_FOLDS_COMMAND in message
    assert str(FOLD_SCHEMA_VERSION) in message


def test_a_fold_manifest_from_a_future_schema_is_refused(tmp_path):
    """Unknown is refused for the same reason stale is: it is not this file."""
    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root)
    path = splits_dir / FOLD_MANIFEST_FILENAME
    written = json.loads(path.read_text(encoding="utf-8"))
    written["schema_version"] = FOLD_SCHEMA_VERSION + 1
    path.write_text(json.dumps(written), encoding="utf-8")

    with pytest.raises(ValueError, match="schema_version"):
        load_folds(str(splits_dir))


# --- repeats_use_distinct_derived_seeds -------------------------------------


def test_repeats_use_distinct_derived_seeds(tmp_path):
    root = write_version(tmp_path)
    _, _, folds = generate(tmp_path, root)

    assert SEED_DERIVATION == "seed_r = data.seed + 1000 * r"
    for repeat in range(REPEATS):
        assert derive_repeat_seed(SEED, repeat) == SEED + 1000 * repeat
        assert folds["seeds"][str(repeat)] == derive_repeat_seed(SEED, repeat)

    assignments = [splittable_assignments(folds, r) for r in range(REPEATS)]
    for first in range(REPEATS):
        for second in range(first + 1, REPEATS):
            assert assignments[first] != assignments[second], (
                f"repeats {first} and {second} share a fold assignment"
            )


def test_the_same_seed_reproduces_the_same_folds(tmp_path):
    """Distinct across repeats, identical across runs: both are the seed's job."""
    root = write_version(tmp_path)
    _, _, first = generate(tmp_path, root)
    _, _, second = generate(tmp_path / "again", root)

    assert first["folds"] == second["folds"]


# --- selection_is_nested ----------------------------------------------------


def test_selection_is_nested(tmp_path):
    """No group of an outer fold's test side is read while selecting for it."""
    manifest, folds = real_folds(tmp_path)

    for repeat in range(REPEATS):
        for fold in range(K):
            test_groups = {
                entry["group"] for entry in fold_split(folds, repeat, fold)["test"]
            }
            read = selection_groups(folds, repeat, fold, inner_k=4)

            assert read, "selection read no group at all"
            assert not (read & test_groups), (
                f"repeat {repeat} fold {fold} selected on its own test groups"
            )


def test_inner_folds_partition_the_training_side_and_keep_train_only_in_training(
    tmp_path,
):
    """The inner loop is the outer training side again, under the same rules."""
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    restricted = {
        row.sample_id for row in manifest.rows if row.sample_id.endswith("-7")
    }
    _, _, folds = generate(tmp_path, root, train_only=restricted)

    outer = fold_split(folds, repeat=0, fold=0)
    training_groups = {entry["group"] for entry in outer["train"]}
    train_only_groups = {
        group_id
        for group_id, record in folds["groups"].items()
        if record["train_only"]
    }

    inner = inner_folds(folds, repeat=0, fold=0, inner_k=4)
    assert len(inner) == 4

    validated = Counter()
    for split in inner:
        inner_train = {entry["group"] for entry in split["train"]}
        inner_val = {entry["group"] for entry in split["val"]}
        assert not (inner_train & inner_val)
        assert inner_train | inner_val <= training_groups
        assert train_only_groups <= inner_train
        assert not (inner_val & train_only_groups)
        for group_id in inner_val:
            validated[group_id] += 1

    assert set(validated) == training_groups - train_only_groups
    assert set(validated.values()) == {1}


# --- refit_uses_the_whole_training_side -------------------------------------


def test_refit_uses_the_whole_training_side(tmp_path):
    """The refit set is every training group, splittable and train-only alike."""
    manifest, folds = real_folds(tmp_path)

    train_only_groups = {
        group_id
        for group_id, record in folds["groups"].items()
        if record["train_only"]
    }

    for repeat in range(REPEATS):
        for fold in range(K):
            split = fold_split(folds, repeat, fold)
            refit_groups = {entry["group"] for entry in split["train"]}
            test_groups = {entry["group"] for entry in split["test"]}

            assert refit_groups | test_groups == set(folds["groups"])
            assert not (refit_groups & test_groups)
            assert train_only_groups <= refit_groups
            assert selection_groups(folds, repeat, fold, inner_k=4) <= refit_groups


# --- shuffled_control_permutes_labels_at_group_level ------------------------


def test_shuffled_control_permutes_labels_at_group_level(tmp_path):
    root = write_version(tmp_path)
    _, _, folds = generate(tmp_path, root)
    split = fold_split(folds, repeat=0, fold=0)

    permuted = permute_labels_by_group(split["train"], seed=1234)

    assert len(permuted) == len(split["train"])
    assert Counter(entry["label"] for entry in permuted) == Counter(
        entry["label"] for entry in split["train"]
    )

    by_group = {}
    for entry in permuted:
        by_group.setdefault(entry["group"], set()).add(entry["label"])
    assert all(len(labels) == 1 for labels in by_group.values()), (
        "labels were permuted across photographs rather than across groups"
    )

    original = {entry["group"]: entry["label"] for entry in split["train"]}
    changed = {g for g, l in by_group.items() if next(iter(l)) != original[g]}
    assert changed, "the permutation left every group with its own label"


def test_shuffled_control_leaves_the_class_name_agreeing_with_the_label(tmp_path):
    """A permuted label with the original class name would poison every count."""
    root = write_version(tmp_path)
    _, _, folds = generate(tmp_path, root)
    split = fold_split(folds, repeat=0, fold=0)

    permuted = permute_labels_by_group(split["train"], seed=7)

    index_to_class = {i: c for c, i in folds["class_to_idx"].items()}
    for entry in permuted:
        assert entry["class"] == index_to_class[entry["label"]]


def test_shuffled_control_is_reproducible_from_its_recorded_seed(tmp_path):
    """The seed is recorded so the control arm can be regenerated exactly."""
    root = write_version(tmp_path)
    _, _, folds = generate(tmp_path, root)
    entries = fold_split(folds, repeat=0, fold=0)["train"]

    first = permute_labels_by_group(entries, seed=99)
    second = permute_labels_by_group(entries, seed=99)
    other = permute_labels_by_group(entries, seed=100)

    assert [e["label"] for e in first] == [e["label"] for e in second]
    assert [e["label"] for e in first] != [e["label"] for e in other]


# --- single_split_path_is_removed -------------------------------------------


def test_single_split_path_is_removed():
    """No code path produces a train/val/test partition any more."""
    import src.dataset as dataset_module

    for gone in (
        "create_splits",
        "create_splits_for_config",
        "load_splits",
        "validate_splits_against_config",
    ):
        assert not hasattr(dataset_module, gone), f"{gone} still exists"


# --- every class reaches every fold, under any scikit-learn version ---------


def test_every_class_reaches_every_fold_test_side(tmp_path):
    """A fold whose test side lacks a class makes its macro-F1 undefined for it.

    `StratifiedGroupKFold` balances approximately and gives no such guarantee —
    scikit-learn 1.5.2 drops a class from a fold on this very fixture where
    1.8.0 does not — so the generator establishes it rather than hoping for it.
    Asserted on a synthetic version so it runs where the archive is absent.
    """
    root = write_version(tmp_path)
    _, _, folds = generate(tmp_path, root)

    for repeat in range(REPEATS):
        for fold in range(K):
            held = {
                folds["groups"][entry["group"]]["class"]
                for entry in fold_split(folds, repeat, fold)["test"]
            }
            assert held == set(folds["classes"]), (
                f"repeat {repeat} fold {fold} tests {sorted(held)}, missing "
                f"{sorted(set(folds['classes']) - held)}"
            )


def test_fold_class_balance_holds_on_a_synthetic_version(tmp_path):
    """The `folds_are_stratified_and_group_aware` tolerance, checkable in CI.

    The criterion's own test reads the real manifest, which is git-ignored and
    absent in CI. This asserts the same tolerance on a fixture that is always
    present, so the balance is checked on the machine that runs the pins.
    """
    root = write_version(tmp_path)
    _, _, folds = generate(tmp_path, root)

    pooled = Counter(record["class"] for record in folds["groups"].values())
    for repeat in range(REPEATS):
        assignments = splittable_assignments(folds, repeat)
        for fold in range(K):
            held = Counter(
                folds["groups"][group_id]["class"]
                for group_id, index in assignments.items()
                if index == fold
            )
            for texture_class, total in pooled.items():
                assert abs(held[texture_class] - total / K) <= 1


# --- the deterministic repair -----------------------------------------------


def test_rebalance_moves_a_class_into_the_fold_that_lacks_it():
    """The repair is what makes the guarantee hold, so it is tested directly.

    Constructed rather than drawn: under the scikit-learn installed here the
    generator happens not to produce an unbalanced assignment, and a repair that
    is only exercised by luck of the library version is a repair nobody tested.
    """
    labels = {f"A::{i}": 0 for i in range(5)}
    labels.update({f"B::{i}": 1 for i in range(5)})
    # Every A group crammed into fold 0; B spread evenly.
    assignment = {f"A::{i}": 0 for i in range(5)}
    assignment.update({f"B::{i}": i for i in range(5)})

    repaired = rebalance_fold_assignment(assignment, labels, splits=5)

    for label in (0, 1):
        held = Counter(
            repaired[group] for group, value in labels.items() if value == label
        )
        assert [held.get(fold, 0) for fold in range(5)] == [1, 1, 1, 1, 1]


def test_rebalance_leaves_an_already_balanced_assignment_untouched():
    """A no-op where nothing is wrong: the seed still decides the assignment."""
    labels = {f"A::{i}": 0 for i in range(10)}
    assignment = {f"A::{i}": i % 5 for i in range(10)}

    assert rebalance_fold_assignment(assignment, labels, splits=5) == assignment


def test_rebalance_keeps_every_group_in_exactly_one_fold():
    """A repair that duplicated or dropped a group would break the partition."""
    labels = {f"A::{i}": 0 for i in range(7)}
    labels.update({f"B::{i}": 1 for i in range(11)})
    assignment = {group: 0 for group in labels}

    repaired = rebalance_fold_assignment(assignment, labels, splits=5)

    assert set(repaired) == set(labels)
    assert all(0 <= fold < 5 for fold in repaired.values())
    for label in (0, 1):
        held = Counter(
            repaired[group] for group, value in labels.items() if value == label
        )
        counts = [held.get(fold, 0) for fold in range(5)]
        assert max(counts) - min(counts) <= 1


def test_rebalance_is_deterministic():
    """Two runs of one input give one output, or the folds are not reproducible."""
    labels = {f"A::{i}": 0 for i in range(9)}
    labels.update({f"B::{i}": 1 for i in range(6)})
    assignment = {group: 2 for group in labels}

    first = rebalance_fold_assignment(assignment, labels, splits=5)
    second = rebalance_fold_assignment(assignment, labels, splits=5)

    assert first == second


def test_rebalance_spreads_a_class_of_exactly_k_groups_one_per_fold():
    """The binding case: at n = k the only balanced answer is one each."""
    labels = {f"A::{i}": 0 for i in range(5)}
    assignment = {f"A::{i}": 0 for i in range(5)}

    repaired = rebalance_fold_assignment(assignment, labels, splits=5)

    assert sorted(repaired.values()) == [0, 1, 2, 3, 4]


def test_rebalance_does_not_move_a_group_between_classes():
    """Only the fold index moves; a group keeps the class it photographs."""
    labels = {f"A::{i}": 0 for i in range(6)}
    labels.update({f"B::{i}": 1 for i in range(6)})
    assignment = {group: 0 for group in labels}

    repaired = rebalance_fold_assignment(assignment, labels, splits=5)

    assert set(repaired) == set(assignment)
    assert all(isinstance(fold, int) for fold in repaired.values())


# --- the library versions the assignment depends on -------------------------


def test_the_fold_manifest_records_the_library_versions_it_was_generated_under(
    tmp_path,
):
    """`StratifiedGroupKFold` assigns differently across scikit-learn versions.

    The seed alone therefore does not reproduce a fold set, which is what the
    spec's Reproducibility section promises; the version is the missing half.
    """
    import numpy
    import sklearn

    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root)

    written = json.loads(
        (splits_dir / FOLD_MANIFEST_FILENAME).read_text(encoding="utf-8")
    )
    assert written["library_versions"] == {
        "scikit_learn": sklearn.__version__,
        "numpy": numpy.__version__,
    }
    assert written["library_versions"] == library_versions()


def test_loading_a_fold_manifest_from_another_library_version_warns(tmp_path):
    """A warning and not a refusal: the assignment is read, never recomputed.

    Refusing would make a stored, valid partition unusable after a dependency
    bump, and regenerating it would move the folds — which is the one thing a
    reader comparing against an existing result must not do silently.
    """
    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root)
    path = splits_dir / FOLD_MANIFEST_FILENAME
    written = json.loads(path.read_text(encoding="utf-8"))
    written["library_versions"]["scikit_learn"] = "0.0.1-not-installed"
    path.write_text(json.dumps(written), encoding="utf-8")

    with pytest.warns(UserWarning, match="0.0.1-not-installed"):
        loaded = load_folds(str(splits_dir))

    assert loaded["folds"] == written["folds"], "the stored assignment is used as is"


def test_loading_a_fold_manifest_from_this_library_version_is_silent(tmp_path):
    """The warning has to mean something, so the matching case must not warn."""
    import warnings

    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root)

    with warnings.catch_warnings():
        warnings.simplefilter("error")
        load_folds(str(splits_dir))


def test_loading_a_fold_manifest_that_records_no_versions_warns(tmp_path):
    """Absent is not the same as matching, and must not read as it."""
    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root)
    path = splits_dir / FOLD_MANIFEST_FILENAME
    written = json.loads(path.read_text(encoding="utf-8"))
    del written["library_versions"]
    path.write_text(json.dumps(written), encoding="utf-8")

    with pytest.warns(UserWarning, match="records no library versions"):
        load_folds(str(splits_dir))


def test_rebalance_repairs_any_assignment_the_generator_could_produce():
    """The version-independent argument that the CI failure cannot recur.

    scikit-learn 1.5.2 cannot be installed on this interpreter, so its exact
    partition is unavailable here. What can be shown is stronger and needs no
    version: whatever assignment the generator hands over, the repair leaves
    every class within one group of every other fold, and present in every fold
    once the class clears k. The class shapes below are the real archive
    (20/20/16/21) and the synthetic fixture (5 x 8).
    """
    import random

    for shape in ((20, 20, 16, 21), (8, 8, 8, 8, 8), (5, 5, 5)):
        labels = {
            f"c{index}::{member:03d}": index
            for index, size in enumerate(shape)
            for member in range(size)
        }
        generator = random.Random(20260901)
        for _ in range(200):
            assignment = {group: generator.randrange(K) for group in labels}

            repaired = rebalance_fold_assignment(assignment, labels, splits=K)

            assert set(repaired) == set(labels), "a group was dropped or invented"
            for index, size in enumerate(shape):
                counts = Counter(
                    repaired[group]
                    for group, label in labels.items()
                    if label == index
                )
                held = [counts.get(fold, 0) for fold in range(K)]
                assert max(held) - min(held) <= 1, (shape, index, held)
                if size >= K:
                    assert min(held) >= 1, (shape, index, held)


# --- SPEC 0046: the archive keeps Siltosa, the folds never see it ----------


def test_siltosa_groups_reach_no_fold(tmp_path):
    """The archive's Siltosa samples stay in the manifest and out of every fold.

    ADR 0019 makes a dataset version a build product of the archive, so the
    three groups are not deleted; ADR 0016 keeps the class out of the first
    model, so they are not partitioned. Both halves are asserted here, because
    asserting only the second would pass over a version that had lost the rows.
    """
    manifest, folds = real_folds(tmp_path)

    # A fold manifest keys a group as "<class>::<sample_id>", not as the bare
    # sample id. Intersecting bare ids with those keys is empty whatever the
    # truth, so the group ids are built in the manifest's own key space and the
    # construction is proved below against a class that *is* partitioned.
    def group_key(texture_class, sample_id):
        return f"{texture_class}::{sample_id}"

    siltosa_groups = {
        group_key("Siltosa", row.sample_id)
        for row in manifest.rows
        if row.texture_class == "Siltosa"
    }
    assert siltosa_groups, "the ingested archive holds no Siltosa row"

    # Anti-vacuity: the same construction over a configured class must find
    # groups that are present. Without this the test above passes on a typo in
    # the separator, which is exactly how it was first written.
    arenosa_groups = {
        group_key("Arenosa", row.sample_id)
        for row in manifest.rows
        if row.texture_class == "Arenosa"
    }
    assert arenosa_groups & set(folds["groups"]), (
        "the group-key construction matches nothing, so the assertion below "
        "would hold whatever the fold manifest contained"
    )

    assert not siltosa_groups & set(folds["groups"]), (
        f"Siltosa group(s) in the fold pool: "
        f"{sorted(siltosa_groups & set(folds['groups']))}"
    )
    for repeat in range(REPEATS):
        assigned = set(folds["folds"][str(repeat)])
        leaked = sorted(siltosa_groups & assigned)
        assert not leaked, f"repeat {repeat} assigns Siltosa group(s) {leaked}"

    # Read off the manifest's own records rather than off the key spelling, so
    # the criterion does not rest on one string format alone.
    assert not [
        key
        for key, group in folds["groups"].items()
        if group["class"] == "Siltosa"
    ]
    assert "Siltosa" not in folds["classes"]


def test_fold_creation_succeeds_at_k_five(tmp_path):
    """Every configured class holds at least k splittable groups, so k = 5 runs.

    This is the refusal A8 existed to clear: `class {name} has only {count}
    splittable sample group(s), but k = {k} folds need at least {k}`. With the
    four-class list it does not fire, and every fold's test side holds one of
    each — which is the property the refusal was protecting.
    """
    _, folds = real_folds(tmp_path)

    assert folds["k"] == K
    assert sorted(folds["classes"]) == sorted(configured_classes())

    for repeat in range(REPEATS):
        by_fold = {}
        for group_id, index in splittable_assignments(folds, repeat).items():
            by_fold.setdefault(index, Counter())[
                folds["groups"][group_id]["class"]
            ] += 1
        assert sorted(by_fold) == list(range(K))
        for index, held in by_fold.items():
            missing = sorted(set(configured_classes()) - set(held))
            assert not missing, (
                f"repeat {repeat} fold {index} holds no {missing}: {dict(held)}"
            )
