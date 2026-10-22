#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import types
import unittest


ROOT = Path(__file__).resolve().parents[2]
PATCH_SCRIPT = ROOT / "macOS/DaisyApp/Resources/patch-litellm-runtime.py"
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("daisy_litellm_patch", PATCH_SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {PATCH_SCRIPT}")
PATCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCH)


SOURCE = """\
class ModelResponse:
    pass

def _assemble_complete_response_from_streaming_chunks(
    result, start_time, end_time, request_kwargs, streaming_chunks, is_async
):
    complete_streaming_response = None

    if isinstance(result, ModelResponse):
        return result

    if result.choices[0].finish_reason is not None:  # if it's the last chunk
        streaming_chunks.append(result)
        complete_streaming_response = "built"
    else:
        streaming_chunks.append(result)
    return complete_streaming_response
"""


class LiteLlmRuntimePatchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.target = Path(self.temporary_directory.name) / "logging_utils.py"
        self.target.write_text(SOURCE, encoding="utf-8", newline="\n")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_patch_handles_empty_choices_and_preserves_final_chunk(self) -> None:
        self.assertEqual(
            PATCH.patch_runtime(self.target, PATCH.PATCHED_VERSION, PATCH.PATCHED_VERSION),
            "patched",
        )
        namespace: dict[str, object] = {}
        exec(compile(self.target.read_text(encoding="utf-8"), str(self.target), "exec"), namespace)
        assemble = namespace["_assemble_complete_response_from_streaming_chunks"]

        empty_chunk = types.SimpleNamespace(choices=[])
        chunks: list[object] = []
        self.assertIsNone(assemble(empty_chunk, None, None, {}, chunks, False))
        self.assertEqual(chunks, [empty_chunk])

        final_chunk = types.SimpleNamespace(
            choices=[types.SimpleNamespace(finish_reason="stop")]
        )
        self.assertEqual(assemble(final_chunk, None, None, {}, chunks, False), "built")
        self.assertEqual(chunks, [empty_chunk, final_chunk])

    def test_patch_is_idempotent(self) -> None:
        PATCH.patch_runtime(self.target, PATCH.PATCHED_VERSION, PATCH.PATCHED_VERSION)
        patched = self.target.read_bytes()
        self.assertEqual(
            PATCH.patch_runtime(self.target, PATCH.PATCHED_VERSION, PATCH.PATCHED_VERSION),
            "already-patched",
        )
        self.assertEqual(self.target.read_bytes(), patched)

    def test_patch_rejects_installed_version_mismatch(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "does not match requested version"):
            PATCH.patch_runtime(self.target, "1.100.0", PATCH.PATCHED_VERSION)

    def test_patch_rejects_unexpected_supported_source(self) -> None:
        self.target.write_text("unexpected source\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "Refusing to patch unexpected"):
            PATCH.patch_runtime(self.target, PATCH.PATCHED_VERSION, PATCH.PATCHED_VERSION)

    def test_other_exact_versions_are_left_untouched(self) -> None:
        original = self.target.read_bytes()
        self.assertEqual(PATCH.patch_runtime(self.target, "1.102.0", "1.102.0"), "not-required")
        self.assertEqual(self.target.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
