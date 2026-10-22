#!/usr/bin/env python3
"""Apply Daisy's narrowly-scoped LiteLLM runtime compatibility patch."""

from __future__ import annotations

import importlib.metadata
import os
from pathlib import Path
import sys


PATCHED_VERSION = "1.101.0"
TARGET_PATH = Path("litellm/litellm_core_utils/logging_utils.py")
ORIGINAL = "    if result.choices[0].finish_reason is not None:  # if it's the last chunk\n"
HARDENED = (
    "    # Azure-compatible streams may contain usage or metadata chunks without choices.\n"
    "    # Keep those chunks for the eventual stream builder, but do not index choices[0].\n"
    "    if not result.choices:\n"
    "        streaming_chunks.append(result)\n"
    "        return None\n"
    "\n"
    + ORIGINAL
)


def patch_runtime(target: Path, installed_version: str, requested_version: str) -> str:
    """Patch *target* once and return ``patched``, ``already-patched``, or ``not-required``."""

    if installed_version != requested_version:
        raise RuntimeError(
            f"Installed LiteLLM {installed_version} does not match requested version {requested_version}."
        )
    if requested_version != PATCHED_VERSION:
        return "not-required"

    source = target.read_text(encoding="utf-8")
    if source.count(HARDENED) == 1:
        return "already-patched"
    if HARDENED in source or source.count(ORIGINAL) != 1:
        raise RuntimeError(
            f"Refusing to patch unexpected LiteLLM {requested_version} source at {target}."
        )

    patched_source = source.replace(ORIGINAL, HARDENED)
    temporary = target.with_name(f".{target.name}.daisy.tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(patched_source)
        os.chmod(temporary, target.stat().st_mode)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return "patched"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        raise SystemExit("usage: patch-litellm-runtime.py <requested-version>")

    requested_version = argv[1]
    distribution = importlib.metadata.distribution("litellm")
    target = Path(distribution.locate_file(TARGET_PATH))
    result = patch_runtime(target, distribution.version, requested_version)
    print(f"LiteLLM runtime patch: {result}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
