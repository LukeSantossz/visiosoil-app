"""The model adapter: parsing, and what it refuses to guess at.

Everything model-specific lives behind this seam, so these are the tests that
stop a model's phrasing from becoming a silent decision.
"""

import pytest

from src.llm import (
    RELEVANCE_THRESHOLD,
    ModelRefused,
    OllamaClient,
    parse_json_object,
    parse_score,
    parse_yes_no,
    quote_in_evidence,
)


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


def _tags(*entries):
    """A `/api/tags` payload: one entry per local model, as Ollama lists it."""
    return {
        "models": [
            {"name": name, "model": name, "digest": digest}
            for name, digest in entries
        ]
    }


class TestModelDigest:
    """The digest comes from `GET /api/tags` (SPEC 0151).

    `/api/show` carries no `digest` field, so reading it there failed every
    real run while a test that faked the field passed.
    """

    def test_the_digest_is_read_from_the_tags_list(self):
        requested = []

        def get(url):
            requested.append(url)
            return _tags(("llama3.1:8b", "other"), ("qwen2.5:7b", "sha256:abc"))

        client = OllamaClient(get=get)

        assert client.model_digest() == "sha256:abc"
        assert requested and requested[0].endswith("/api/tags")

    def test_an_untagged_model_matches_its_latest_entry(self):
        client = OllamaClient(
            model="qwen2.5", get=lambda url: _tags(("qwen2.5:latest", "sha256:def"))
        )

        assert client.model_digest() == "sha256:def"

    def test_a_model_the_server_does_not_list_is_refused(self):
        client = OllamaClient(get=lambda url: _tags(("llama3.1:8b", "sha256:abc")))

        with pytest.raises(ModelRefused, match="qwen2.5:7b"):
            client.model_digest()

    def test_a_digest_that_is_not_a_string_is_refused(self):
        # `str()` on a mapping or a list produces a plausible-looking value that
        # identifies nothing, and `RunManifest` performs no runtime type check,
        # so it would reach `modelDigest` and void the one promise the manifest
        # exists to make.
        for reported in ({"sha256": "abc"}, ["sha256:abc"], 12345, "", "  "):
            client = OllamaClient(
                get=lambda url, r=reported: _tags(("qwen2.5:7b", r))
            )

            with pytest.raises(ModelRefused, match="digest"):
                client.model_digest()

    def test_an_unreadable_digest_fails_rather_than_becoming_unknown(self):
        """The run manifest is the reproducibility guarantee ADR 0023 put in
        place of a spend ledger. A corpus generated against a model nobody can
        name does not reproduce, so the lookup failing must stop the build
        instead of writing "unknown" into the record."""

        def failing_get(url):
            raise OSError("ollama is not running")

        client = OllamaClient(get=failing_get)

        with pytest.raises(OSError):
            client.model_digest()


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
        grades, grades_requests = recording_client("3")
        grounds, grounds_requests = recording_client('{"trecho": "Z", "sustenta": "sim"}')

        grades.grade_document("consulta", document(passage))
        grounds.is_grounded("afirmação", [passage])

        requests = grades_requests + grounds_requests
        assert len(requests) == 2
        assert all(passage in request["prompt"] for request in requests)

    def test_every_request_pins_the_context_length(self):
        """The server's default context is chosen from the machine's video
        memory — 4096 tokens on one with none — so without this the same model
        and seed read different prompts on different machines."""
        from src.llm import CONTEXT_TOKENS

        queries, queries_requests = recording_client('{"query": "a"}')
        queries.transform_query("Solo argiloso", topic="calagem")
        grades, grades_requests = recording_client("3")
        grades.grade_document("consulta", document("Texto."))
        grounds, grounds_requests = recording_client(
            '{"trecho": "Texto.", "sustenta": "sim"}'
        )
        grounds.is_grounded("afirmação", ["Texto."])
        cells, cells_requests = recording_client(
            '{"status": "grounded", "tips": [], "limitations": []}'
        )
        cells.generate_cell("Argilosa|tb_oxidic", [document("Texto.")])

        requests = queries_requests + grades_requests + grounds_requests + cells_requests
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


def test_the_topic_reaches_the_prompt():
    """One query is written per management topic, so the prompt names the
    topic as well as the soil (SPEC 0153)."""
    client, requests = recording_client('{"query": "Como corrigir o fósforo?"}')

    query = client.transform_query("Solo argiloso intemperizado", topic="fósforo")

    assert query == "Como corrigir o fósforo?"
    assert "Solo argiloso intemperizado" in requests[0]["prompt"]
    assert "fósforo" in requests[0]["prompt"]


@pytest.mark.parametrize(
    "reply",
    ['{}', '{"query": "  "}', '{"query": 3}', '{"query": ["a", "b"]}'],
)
def test_a_reply_without_one_query_is_refused(reply):
    """A list is refused rather than cut to its first item: one query was
    asked for, and taking one of several would be this module choosing."""
    client, _ = recording_client(reply)

    with pytest.raises(ModelRefused):
        client.transform_query("Solo argiloso", topic="calagem")


def test_the_prompt_versions_moved():
    """The transform prompt now writes one query about one topic (SPEC 0153);
    the generate prompt names the key `Solo` rather than `Chave` (SPEC 0152)."""
    versions = OllamaClient().prompt_versions

    assert versions["transform"] == "3"
    assert versions["generate"] == "3"


# --- The grader scores relevance (SPEC 0154) -----------------------------------


@pytest.mark.parametrize("reply, relevant", [("0", False), ("1", False), ("2", True), ("3", True)])
def test_a_score_at_or_above_the_threshold_is_relevant(reply, relevant):
    """A single `sim`/`não` dropped CT 33 on one wording of the phosphorus query
    and kept it on four others; on a 0-3 scale it scores 2 on all five."""
    client, _ = recording_client(reply)

    assert client.grade_document("consulta", document("Texto.")) is relevant


@pytest.mark.parametrize(
    "reply, score", [("2", 2), ("Nota: 3.", 3), (" 0 ", 0), ("**1**", 1)]
)
def test_a_score_is_read_through_prose(reply, score):
    assert parse_score(reply) == score


@pytest.mark.parametrize(
    "reply", ["", "sim", "talvez", "2 ou 3", "2/3", "4", "10", "-1", "-3", "−2"]
)
def test_a_reply_without_one_score_is_refused(reply):
    """A hedge between two scores is refused rather than resolved, for the
    reason `parse_yes_no` refuses "sim e não"."""
    with pytest.raises(ModelRefused):
        parse_score(reply)


def test_the_scale_reaches_the_prompt():
    client, requests = recording_client("2")

    client.grade_document("adubação fosfatada", document("Circular técnica."))

    prompt = requests[0]["prompt"]
    assert "adubação fosfatada" in prompt
    assert "Circular técnica." in prompt
    for step in ("0 —", "1 —", "2 —", "3 —"):
        assert step in prompt


def test_the_grade_prompt_version_moved():
    assert OllamaClient().prompt_versions["grade"] == "2"


def test_the_threshold_is_two():
    assert RELEVANCE_THRESHOLD == 2


# --- The grounding check verifies a quote (SPEC 0155) ---------------------------

CT33 = (
    "Em sistemas de menor risco, sugere-se elevar o teor de P ao limite superior "
    "da classe adequada, ou seja, 90% do rendimento poten- cial, de modo que os "
    "níveis críticos serão iguais a 25 mg dm-3."
)


def grounding_reply(quote, verdict="sim"):
    import json

    return json.dumps({"trecho": quote, "sustenta": verdict}, ensure_ascii=False)


def test_a_supported_claim_quoted_from_the_evidence_is_grounded():
    client, _ = recording_client(
        grounding_reply("sugere-se elevar o teor de P ao limite superior")
    )

    assert client.is_grounded("Eleve o P ao limite superior.", [CT33]) is True


def test_a_quote_not_in_the_evidence_is_not_grounded():
    """The B1' tip: the model said `sim` and quoted the claim's own words, which
    CT 33 does not hold. Only the check of the passage refuses it."""
    client, _ = recording_client(
        grounding_reply(
            "a adubação fosfatada deve ser ajustada para alcançar 90% do "
            "rendimento potencial"
        )
    )

    assert client.is_grounded("Ajuste a adubação para 90%.", [CT33]) is False


def test_a_não_verdict_is_not_grounded():
    client, _ = recording_client(
        grounding_reply("sugere-se elevar o teor de P", verdict="não")
    )

    assert client.is_grounded("Solos argilosos dispensam fósforo.", [CT33]) is False


@pytest.mark.parametrize("quote", ["", "   "])
def test_a_blank_quote_is_not_grounded(quote):
    client, _ = recording_client(grounding_reply(quote))

    assert client.is_grounded("Qualquer afirmação.", [CT33]) is False


@pytest.mark.parametrize(
    "quote",
    [
        "90% do rendimento potencial",
        "90%   do rendimento\npoten- cial",
        "LIMITE SUPERIOR DA CLASSE ADEQUADA",
    ],
)
def test_a_quote_matches_across_a_line_break_hyphen(quote):
    """The extracted PDF text reads "poten- cial"; a model copying it writes
    "potencial". Without joining the break a true claim was refused."""
    assert quote_in_evidence(quote, [CT33]) is True


def test_a_quote_past_what_the_model_saw_is_not_found():
    from src.sources import PASSAGE_CHAR_LIMIT

    text = "a" * PASSAGE_CHAR_LIMIT + " trecho que o modelo não leu"

    assert quote_in_evidence("trecho que o modelo não leu", [text]) is False


def test_a_quote_from_any_cited_text_counts():
    assert quote_in_evidence("níveis críticos", ["Outro documento.", CT33]) is True


@pytest.mark.parametrize(
    "reply",
    [
        "sim",
        '{"trecho": "90% do rendimento", "sustenta": "talvez"}',
        '{"trecho": 90, "sustenta": "sim"}',
    ],
)
def test_a_malformed_grounding_reply_is_refused(reply):
    client, _ = recording_client(reply)

    with pytest.raises(ModelRefused):
        client.is_grounded("Qualquer afirmação.", [CT33])


def test_the_claim_and_evidence_reach_the_prompt():
    client, requests = recording_client(grounding_reply("níveis críticos"))

    client.is_grounded("Os níveis críticos dependem da argila.", [CT33])

    prompt = requests[0]["prompt"]
    assert "Os níveis críticos dependem da argila." in prompt
    assert CT33 in prompt
    assert "palavra por palavra" in prompt
    assert '"trecho"' in prompt


def test_the_ground_prompt_version_moved():
    assert OllamaClient().prompt_versions["ground"] == "2"
