from __future__ import annotations

import csv
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "data" / "build_flutter_staging_asset.py"
INPUT_PATH = PROJECT_ROOT / "tests" / "fixtures" / "virtual_yongsan_staging.csv"

spec = importlib.util.spec_from_file_location("build_flutter_staging_asset", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
asset_builder = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = asset_builder
spec.loader.exec_module(asset_builder)


class FlutterStagingAssetTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temp_path = Path(self.temporary_directory.name)
        self.rows = asset_builder.read_staging_rows(INPUT_PATH)

    def write_rows(self, rows) -> Path:
        path = self.temp_path / "input.csv"
        with path.open("w", encoding="utf-8-sig", newline="") as output_file:
            writer = csv.DictWriter(output_file, fieldnames=list(self.rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        return path

    def test_synthetic_staging_converts_exactly_24_minimal_items(self) -> None:
        output_path = self.temp_path / "staging.json"

        items = asset_builder.write_asset(INPUT_PATH, output_path)
        saved = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual(len(items), 24)
        self.assertEqual(len(saved), 24)
        self.assertEqual(len({item["id"] for item in saved}), 24)
        self.assertTrue(all(item["verificationStatus"] == "pending" for item in saved))
        self.assertTrue(all(item["burgerStyle"] == "미분류" for item in saved))
        self.assertTrue(
            all(set(item) == asset_builder.ALLOWED_OUTPUT_FIELDS for item in saved)
        )
        serialized = output_path.read_text(encoding="utf-8")
        for forbidden in (
            "sourcePlaceId",
            "matchedCandidateId",
            "placeUrl",
            "sourceCategory",
            "sourceStoreId",
            "provenanceNote",
        ):
            self.assertNotIn(forbidden, serialized)
        names = {item["name"] for item in saved}
        self.assertTrue(asset_builder.FORBIDDEN_INPUT_NAMES.isdisjoint(names))

    def test_rejects_duplicate_id(self) -> None:
        rows = [dict(row) for row in self.rows]
        rows[1]["candidateId"] = rows[0]["candidateId"]

        with self.assertRaises(asset_builder.FlutterAssetError):
            asset_builder.convert_rows(rows)

    def test_rejects_missing_required_value(self) -> None:
        rows = [dict(row) for row in self.rows]
        rows[0]["displayName"] = ""

        with self.assertRaises(asset_builder.FlutterAssetError):
            asset_builder.convert_rows(rows)

    def test_rejects_invalid_coordinate(self) -> None:
        rows = [dict(row) for row in self.rows]
        rows[0]["latitude"] = "91"

        with self.assertRaises(asset_builder.FlutterAssetError):
            asset_builder.convert_rows(rows)

    def test_rejects_every_non_pending_status(self) -> None:
        for status in ("verified", "rejected", "needs_recheck"):
            with self.subTest(status=status):
                rows = [dict(row) for row in self.rows]
                rows[0]["verificationStatus"] = status
                with self.assertRaises(asset_builder.FlutterAssetError):
                    asset_builder.convert_rows(rows)
        rows = [dict(row) for row in self.rows]
        rows[0]["stagingStatus"] = "hold_needs_recheck"
        with self.assertRaises(asset_builder.FlutterAssetError):
            asset_builder.convert_rows(rows)

    def test_rejects_hold_store_name(self) -> None:
        rows = [dict(row) for row in self.rows]
        rows[0]["displayName"] = "다운타우너 한남"

        with self.assertRaises(asset_builder.FlutterAssetError):
            asset_builder.convert_rows(rows)


if __name__ == "__main__":
    unittest.main()
