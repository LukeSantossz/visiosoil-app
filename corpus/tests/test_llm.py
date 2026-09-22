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

    def test_a_digest_that_is_not_a_string_is_refused(self):
        # `str()` on a mapping or a list produces a plausible-looking value that
        # identifies nothing, and `RunManifest` performs no runtime type check,
        # so it would reach `modelDigest` and void the one promise the manifest
        # exists to make.
        for reported in ({"sha256": "abc"}, ["sha256:abc"], 12345):
            client = OllamaClient(post=lambda url, payload, r=reported: {"digest": r})

            with pytest.raises(ModelRefused, match="digest"):
                client.model_digest()

    def test_a_reported_digest_is_returned(self):
        client = OllamaClient(post=lambda url, payload: {"digest": "sha256:abc"})

        assert client.model_digest() == "sha256:abc"


# --- The transport hands a PDF over undecoded -----------------------------------


class TestResponseBody:
    def test_a_pdf_body_is_passed_through_undecoded(self):
        """A PDF is binary. Decoding it as text would hand the HTML extractor
        whatever survived, and it returns that instead of failing."""
        from src.llm import decode_body
        from tests.pdf_documents import make_pdf

        pdf = make_pdf(["Texto."])

        body = decode_body(pdf, "utf-8")

        assert isinstance(body, bytes)
        assert body == pdf

    def test_an_html_body_is_decoded_with_its_charset(self):
        from src.llm import decode_body

        raw = "<p>Adubação e calagem</p>".encode("iso-8859-1")

        assert decode_body(raw, "iso-8859-1") == "<p>Adubação e calagem</p>"
        assert decode_body("<p>ação</p>".encode("utf-8"), None) == "<p>ação</p>"


# --- The model reads everything it is given ------------------------------------


def recording_client(response):
    """An `OllamaClient` whose server answers [response] and records each
    request, so a test can read exactly what would have reached the model."""
    requests = []

    def post(url, payload):
        requests.append(payload)
        return {"response": response}

    return OllamaClient(post=post), requests


def document(text):
    from src.sources import FetchedSource

    return FetchedSource(
        url="https://example.org/a.pdf",
        title="Fonte",
        publisher="Embrapa",
        tier=1,
        text=text,
        digest="0" * 64,
    )


class TestTheModelReadsAllOfIt:
    def test_a_passage_at_the_budget_reaches_the_prompt_whole(self):
        """The client's cut and the fetch's refusal are one number. If they
        drifted apart, a passage the fetch accepted would still be cut."""
        from src.sources import PASSAGE_CHAR_LIMIT

        passage = "a" * (PASSAGE_CHAR_LIMIT - 1) + "Z"
        client, requests = recording_client("sim")

        client.grade_document("consulta", document(passage))
        client.is_grounded("afirmação", [passage])

        assert all(passage in request["prompt"] for request in requests)

    def test_every_request_pins_the_context_length(self):
        """The server's default context is chosen from the machine's video
        memory — 4096 tokens on one with none — so without this the same model
        and seed read different prompts on different machines."""
        from src.llm import CONTEXT_TOKENS

        queries, queries_requests = recording_client('{"queries": ["a", "b", "c"]}')
        queries.transform_queries("Argilosa|tb_oxidic", count=3)
        grades, grades_requests = recording_client("sim")
        grades.grade_document("consulta", document("Texto."))
        grades.is_grounded("afirmação", ["Texto."])
        cells, cells_requests = recording_client(
            '{"status": "grounded", "tips": [], "limitations": []}'
        )
        cells.generate_cell("Argilosa|tb_oxidic", [document("Texto.")])

        requests = queries_requests + grades_requests + cells_requests
        assert len(requests) == 4
        assert all(r["options"]["num_ctx"] == CONTEXT_TOKENS for r in requests)

    def test_a_prompt_longer_than_the_context_is_refused_before_it_is_sent(self):
        """A manifest listing more passages than the context holds would be cut
        by the server without a word. It is refused here, before anything is
        sent."""
        from src.llm import PROMPT_CHAR_CEILING
        from src.sources import PASSAGE_CHAR_LIMIT

        too_many = PROMPT_CHAR_CEILING // PASSAGE_CHAR_LIMIT + 1
        client, requests = recording_client("{}")

        with pytest.raises(ModelRefused, match="context"):
            client.generate_cell(
                "Argilosa|tb_oxidic",
                [document("a" * PASSAGE_CHAR_LIMIT) for _ in range(too_many)],
            )

        assert requests == []


def test_a_pdf_signature_after_leading_bytes_is_still_not_decoded():
    """Readers find the signature anywhere in the first 1024 bytes. A PDF behind
    a stray byte-order mark, decoded as text, would reach the HTML extractor and
    come back as binary noise that passes as prose; kept as bytes, the fetch
    refuses it because it does not open with the signature."""
    from src.llm import decode_body
    from tests.pdf_documents import make_pdf

    mangled = b"\xef\xbb\xbf" + make_pdf(["Texto."])

    assert decode_body(mangled, "utf-8") == mangled
