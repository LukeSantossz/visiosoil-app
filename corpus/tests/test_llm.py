"""The model adapter: parsing, and what it refuses to guess at.

Everything model-specific lives behind this seam, so these are the tests that
stop a model's phrasing from becoming a silent decision.
"""

import pytest

from src.llm import ModelRefused, OllamaClient, parse_json_object, parse_yes_no


class TestParseYesNo:
    def test_a_plain_yes_and_no(self):
        assert parse_yes_no("sim") is True
        assert parse_yes_no("não") is False
        assert parse_yes_no("yes") is True
        assert parse_yes_no("no") is False

    def test_a_negated_positive_is_negative(self):
        """The bug this test exists for.

        "não relevante" contains `relevante`. A loop that checks positives first
        returns True and the grader keeps a source the model explicitly
        rejected — silently, on every cell.
        """
        assert parse_yes_no("não relevante") is False
        assert parse_yes_no("nao relevante") is False
        assert parse_yes_no("not relevant") is False

    def test_an_answer_carrying_both_polarities_is_refused(self):
        # "sim e não" is not an answer, and picking whichever token comes first
        # would turn a model's hedge into a decision nobody made.
        with pytest.raises(ModelRefused):
            parse_yes_no("sim e não")
        with pytest.raises(ModelRefused):
            parse_yes_no("no, mas sim")

    def test_a_negation_attached_to_the_positive_word_still_reads_negative(self):
        # This one is not ambiguous, and an earlier version of this test wrongly
        # said it was: "não relevante o suficiente" means not relevant.
        assert parse_yes_no("relevante, mas não relevante o suficiente") is False

    def test_an_answer_with_neither_polarity_is_refused(self):
        with pytest.raises(ModelRefused):
            parse_yes_no("talvez")
        with pytest.raises(ModelRefused):
            parse_yes_no("")

    def test_surrounding_prose_and_punctuation_do_not_break_it(self):
        assert parse_yes_no("Sim.") is True
        assert parse_yes_no("  NÃO  ") is False


class TestParseJsonObject:
    def test_a_bare_object(self):
        assert parse_json_object('{"a": 1}') == {"a": 1}

    def test_a_fenced_object(self):
        assert parse_json_object('```json\n{"a": 1}\n```') == {"a": 1}

    def test_prose_around_an_object(self):
        assert parse_json_object('Claro:\n{"a": 1}\nEspero ter ajudado.') == {"a": 1}

    def test_no_object_is_refused(self):
        with pytest.raises(ModelRefused):
            parse_json_object("desculpe, não posso")

    def test_a_json_array_is_refused(self):
        with pytest.raises(ModelRefused):
            parse_json_object("[1, 2]")


class TestModelDigest:
    def test_an_unreadable_digest_fails_rather_than_becoming_unknown(self):
        """The run manifest is the reproducibility guarantee ADR 0023 put in
        place of a spend ledger. A corpus generated against a model nobody can
        name does not reproduce, so the lookup failing must stop the build
        instead of writing "unknown" into the record."""

        def failing_post(url, payload):
            raise OSError("ollama is not running")

        client = OllamaClient(post=failing_post)

        with pytest.raises(OSError):
            client.model_digest()

    def test_a_digest_the_server_does_not_report_is_refused(self):
        client = OllamaClient(post=lambda url, payload: {"model_info": {}})

        with pytest.raises(ModelRefused):
            client.model_digest()

    def test_a_reported_digest_is_returned(self):
        client = OllamaClient(post=lambda url, payload: {"digest": "sha256:abc"})

        assert client.model_digest() == "sha256:abc"
