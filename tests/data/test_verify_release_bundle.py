from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "release" / "verify_release_bundle.py"
SPEC = importlib.util.spec_from_file_location("verify_release_bundle", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ReleaseBundleVerificationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.staging_json = self.root / "staging.json"
        self.staging_json.write_text(
            json.dumps(
                [
                    {
                        "id": "synthetic-candidate-001",
                        "name": "Synthetic Burger Lab",
                        "address": "Synthetic district 1",
                    }
                ]
            ),
            encoding="utf-8",
        )

    def _bundle(self, entries: dict[str, bytes]) -> Path:
        path = self.root / f"bundle-{len(list(self.root.glob('bundle-*')))}.aab"
        with zipfile.ZipFile(path, "w") as bundle:
            for name, content in entries.items():
                bundle.writestr(name, content)
        return path

    def test_project_packages_staging_asset_from_debug_source_set_only(self) -> None:
        pubspec = (PROJECT_ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        gradle = (PROJECT_ROOT / "android" / "app" / "build.gradle.kts").read_text(
            encoding="utf-8"
        )

        self.assertNotIn("- assets/dev/", pubspec)
        self.assertIn("prepareDebugStagingAssets", gradle)
        self.assertIn('getByName("debug").assets.srcDir', gradle)
        self.assertIn('it.name == "mergeDebugAssets"', gradle)
        self.assertNotIn('getByName("release").assets.srcDir', gradle)

    def test_safe_synthetic_bundle_passes(self) -> None:
        bundle = self._bundle(
            {
                "base/assets/flutter_assets/AssetManifest.bin": b"safe-asset",
                "base/lib/arm64-v8a/libapp.so": b"safe-binary",
            }
        )

        inspection = MODULE.inspect_release_bundle(
            bundle,
            staging_json_path=self.staging_json,
        )

        self.assertTrue(inspection.is_safe)
        self.assertEqual(inspection.forbidden_entry_hits, 0)
        self.assertEqual(inspection.asset_manifest_hits, 0)
        self.assertEqual(inspection.staging_value_hits, 0)

    def test_staging_zip_entry_fails(self) -> None:
        bundle = self._bundle(
            {
                "base/assets/flutter_assets/assets/dev/"
                "yongsan_burger_stores_staging.json": b"[]"
            }
        )

        inspection = MODULE.inspect_release_bundle(bundle)

        self.assertFalse(inspection.is_safe)
        self.assertEqual(inspection.forbidden_entry_hits, 1)

    def test_staging_asset_manifest_entry_fails(self) -> None:
        bundle = self._bundle(
            {
                "base/assets/flutter_assets/AssetManifest.bin": (
                    b"assets/dev/yongsan_burger_stores_staging.json"
                )
            }
        )

        inspection = MODULE.inspect_release_bundle(bundle)

        self.assertFalse(inspection.is_safe)
        self.assertEqual(inspection.asset_manifest_hits, 1)

    def test_staging_identity_in_bundle_fails_without_logging_values(self) -> None:
        synthetic_id = "synthetic-candidate-001"
        synthetic_name = "Synthetic Burger Lab"
        synthetic_key = "AIza" + "A" * 35
        bundle = self._bundle(
            {
                "base/lib/arm64-v8a/libapp.so": (
                    f"{synthetic_id}|{synthetic_name}|{synthetic_key}".encode()
                )
            }
        )

        inspection = MODULE.inspect_release_bundle(
            bundle,
            staging_json_path=self.staging_json,
        )
        summary = MODULE.format_summary(inspection)

        self.assertFalse(inspection.is_safe)
        self.assertGreaterEqual(inspection.staging_value_hits, 2)
        self.assertEqual(inspection.secret_pattern_hits, 1)
        self.assertNotIn(synthetic_id, summary)
        self.assertNotIn(synthetic_name, summary)
        self.assertNotIn(synthetic_key, summary)

    def test_short_name_tokens_do_not_create_binary_false_positives(self) -> None:
        self.staging_json.write_text(
            json.dumps(
                [
                    {
                        "id": "synthetic-candidate-001",
                        "name": "X",
                        "address": "Synthetic district 1",
                    }
                ]
            ),
            encoding="utf-8",
        )
        bundle = self._bundle({"base/lib/arm64-v8a/libapp.so": b"binary-X-data"})

        inspection = MODULE.inspect_release_bundle(
            bundle,
            staging_json_path=self.staging_json,
        )

        self.assertTrue(inspection.is_safe)
        self.assertEqual(inspection.staging_value_hits, 0)

    def test_cli_returns_nonzero_without_printing_staging_values(self) -> None:
        bundle = self._bundle(
            {"base/data.bin": b"synthetic-candidate-001"}
        )
        stdout = io.StringIO()
        stderr = io.StringIO()

        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            result = MODULE.main(
                [
                    "--bundle",
                    str(bundle),
                    "--staging-json",
                    str(self.staging_json),
                ]
            )

        output = stdout.getvalue() + stderr.getvalue()
        self.assertEqual(result, 1)
        self.assertNotIn("synthetic-candidate-001", output)
        self.assertNotIn("Synthetic Burger Lab", output)


if __name__ == "__main__":
    unittest.main()
