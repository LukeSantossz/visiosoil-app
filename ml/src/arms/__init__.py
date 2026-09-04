"""The fold trainers of the arms E0 compares (SPEC 0044, SPEC 0054).

Every arm is a fold trainer with :func:`src.train.train_fold`'s signature, and
``crossval.run_arm`` dispatches on the arm name. That is what lets the protocol
read a completed arm without knowing which one it was: the artifacts, the
pooling, the contrasts and the minimum detectable effect are all written against
one shape.

:mod:`src.arms.probe` is the machinery the two linear-probe arms share. Both are
a featuriser plus a multinomial logistic regression, and the only difference
between them is where the features come from, so the protocol — the nesting, the
standardisation, the patch aggregation — is implemented once and parameterised
by the featuriser rather than written twice and compared.
"""

from .probe import Featuriser, probe_fold

__all__ = ["Featuriser", "probe_fold"]
