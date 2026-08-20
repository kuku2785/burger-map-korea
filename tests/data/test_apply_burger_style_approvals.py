from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
TEST_DIR = Path(__file__).resolve().parent
if str(TEST_DIR) not in sys.path:
    sys.path.insert(0, str(TEST_DIR))
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "data" / "apply_burger_style_approvals.py"

spec = importlib.util.spec_from_file_location("apply_burger_style_approvals", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
approval_tool = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = approval_tool
spec.loader.exec_module(approval_tool)

from style_review_test_utils import make_style_review_rows, write_style_review


class BurgerStyleApprovalTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.path = Path(self.temporary_directory.name) / "style-review.csv"
        identities = [
            {
                "candidateId": f"candidate-{index}",
                "name": f"가상 매장 {index}",
                "address": f"서울 용산구 가상로 {index}",
            }
            for index in range(1, 4)
        ]
        self.rows = make_style_review_rows(
            identities,
            {1: "classic", 2: "smash"},
        )
        write_style_review(
            self.path,
            approval_tool.STYLE_REVIEW_HEADERS,
            self.rows,
        )

    def test_applies_only_explicit_approvals_and_is_idempotent(self) -> None:
        approvals = {"1": "classic", "2": "smash"}
        before_immutable = [
            tuple(row[field] for field in ("reviewNumber", "storeId", "candidateId", "name", "address"))
            for row in self.rows
        ]

        count = approval_tool.apply_approvals_to_file(self.path, approvals)
        first_bytes = self.path.read_bytes()
        second_count = approval_tool.apply_approvals_to_file(self.path, approvals)
        second_bytes = self.path.read_bytes()
        output = approval_tool.read_validated_style_review_rows(self.path)

        self.assertEqual(count, 2)
        self.assertEqual(second_count, 2)
        self.assertEqual(first_bytes, second_bytes)
        self.assertEqual([row["reviewStatus"] for row in output], ["approved", "approved", "needs_recheck"])
        self.assertEqual(output[2]["proposedBurgerStyle"], "unclassified")
        self.assertEqual(
            [tuple(row[field] for field in ("reviewNumber", "storeId", "candidateId", "name", "address")) for row in output],
            before_immutable,
        )

    def test_blocks_style_mismatch_and_approval_outside_the_list(self) -> None:
        original = self.path.read_bytes()
        with self.assertRaises(approval_tool.StorePublishingError):
            approval_tool.apply_approvals_to_file(self.path, {"1": "chicken"})
        self.assertEqual(self.path.read_bytes(), original)

        rows = approval_tool.read_validated_style_review_rows(self.path)
        rows[1]["reviewStatus"] = "approved"
        rows[1]["reviewerNote"] = "이전 사용자 승인"
        write_style_review(self.path, approval_tool.STYLE_REVIEW_HEADERS, rows)
        with self.assertRaises(approval_tool.StorePublishingError):
            approval_tool.apply_approvals_to_file(self.path, {"1": "classic"})


if __name__ == "__main__":
    unittest.main()
