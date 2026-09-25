#!/usr/bin/env python3
"""Render Codex TOML agents from shared persona instructions and metadata."""

import json
import sys
from pathlib import Path


def metadata(path: Path) -> dict[str, str]:
    values = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition(":")
        if not separator or not key.strip() or not value.strip():
            raise ValueError(f"Invalid metadata line in {path}: {line!r}")
        if key.strip() in values:
            raise ValueError(f"Duplicate metadata key in {path}: {key.strip()}")
        values[key.strip()] = value.strip()
    required = {"name", "description", "model"}
    if set(values) != required:
        raise ValueError(f"Expected {sorted(required)} in {path}; got {sorted(values)}")
    return values


def main(source: Path, target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    for persona in sorted(source.iterdir()):
        if not persona.is_dir():
            continue
        meta = metadata(persona / "codex.yaml")
        if meta["name"] != persona.name:
            raise ValueError(f"Agent name must match directory: {persona}")
        instructions = (persona / "instructions.md").read_text()
        fields = {**meta, "developer_instructions": instructions}
        output = "".join(f"{key} = {json.dumps(value, ensure_ascii=False)}\n" for key, value in fields.items())
        (target / f"{persona.name}.toml").write_text(output)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
