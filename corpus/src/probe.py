"""The calibration probe: one cell, end to end, with a local model.

It answers the question ADR 0023 left open — whether a 7-8 B local model can
grade sources and generate cited guidance well enough to be worth an
agronomist's time — by building one cell and putting it in front of one. A
judgement of "not worth reading" is a result, and it stops the plan before the
other 43 cells exist.

**Its output never lands in `assets/corpus/`.** Unreviewed generated guidance
must not sit where the app loads reviewed guidance from; moving it there is the
review gate's act, and that gate is blocked on a reviewer nobody has identified.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from src.manifest import RunManifest

DEFAULT_OUT_DIR = Path(__file__).resolve().parent.parent / "out"
DEFAULT_MANIFEST = (
    Path(__file__).resolve().parent.parent / "sources" / "substance.manifest.json"
)


@dataclass(frozen=True)
class WrittenOutput:
    cell_path: Path
    manifest_path: Path


def write_output(
    cell: dict[str, Any],
    manifest: RunManifest,
    *,
    out_dir: Path = DEFAULT_OUT_DIR,
) -> WrittenOutput:
    """Writes the cell and its run manifest under [out_dir]."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    slug = manifest.key.replace("|", "__").replace(" ", "-")
    cell_path = out / f"{slug}.cell.json"
    manifest_path = out / f"{slug}.manifest.json"
    cell_path.write_text(
        json.dumps(cell, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    manifest_path.write_text(
        json.dumps(manifest.to_json(), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return WrittenOutput(cell_path=cell_path, manifest_path=manifest_path)


def main(argv: list[str] | None = None) -> int:
    from src.llm import OllamaClient, http_transport
    from src.pipeline import build_cell
    from src.sources import SourceManifest, fetch_sources

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cell", required=True, help='e.g. "Argilosa|tb_oxidic"')
    parser.add_argument("--model", default="qwen2.5:7b")
    parser.add_argument("--seed", type=int, default=1234)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args(argv)

    sources = fetch_sources(
        SourceManifest.load(args.manifest), transport=http_transport
    )
    client = OllamaClient(model=args.model, seed=args.seed)
    outcome = build_cell(args.cell, sources, client=client)

    manifest = RunManifest(
        key=outcome.key,
        model=args.model,
        model_digest=client.model_digest(),
        prompt_versions=client.prompt_versions,
        seed=args.seed,
        sources=outcome.kept,
        attempts=outcome.attempts,
        rejections=outcome.rejections,
    )
    written = write_output(outcome.cell, manifest, out_dir=args.out)
    print(f"cell:     {written.cell_path}")
    print(f"manifest: {written.manifest_path}")
    print(f"status:   {outcome.cell['status']} after {outcome.attempts} attempt(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
