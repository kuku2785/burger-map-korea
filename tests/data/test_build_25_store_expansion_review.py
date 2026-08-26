import csv
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "data" / "build_25_store_expansion_review.py"
SPEC = importlib.util.spec_from_file_location("build_25_store_expansion_review", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class Build25StoreExpansionReviewTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.paths = {
            key: self.root / filename
            for key, filename in {
                "publish": "publish.csv",
                "style": "style.csv",
                "staging": "staging.csv",
                "hold": "hold.csv",
                "kakao": "kakao.csv",
                "candidate": "candidate.csv",
                "evidence": "evidence.json",
                "output": "output.csv",
            }.items()
        }
        self._write_inputs()

    def tearDown(self):
        self.temp_dir.cleanup()

    @staticmethod
    def _write_csv(path, fieldnames, rows):
        with path.open("w", encoding="utf-8-sig", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    def _write_inputs(self):
        publish = [
            {
                "storeId": "11111111-1111-4111-8111-111111111111",
                "candidateId": "virtual_pending_a",
                "name": "가상 버거 A",
                "address": "서울 용산구 가상로 1",
                "latitude": "37.51",
                "longitude": "126.91",
                "burgerStyle": "classic",
                "sourceType": "semas_kakao",
                "sourceAsOf": "2026-06-30",
                "publishDecision": "pending",
                "isActive": "false",
                "verifiedAt": "",
                "verificationNote": "",
            },
            {
                "storeId": "22222222-2222-4222-8222-222222222222",
                "candidateId": "virtual_pending_b",
                "name": "가상 버거 B",
                "address": "서울 용산구 가상로 2",
                "latitude": "37.52",
                "longitude": "126.92",
                "burgerStyle": "unclassified",
                "sourceType": "kakao",
                "sourceAsOf": "2026-06-30",
                "publishDecision": "pending",
                "isActive": "false",
                "verifiedAt": "",
                "verificationNote": "",
            },
            {
                "storeId": "33333333-3333-4333-8333-333333333333",
                "candidateId": "virtual_public",
                "name": "가상 공개 버거",
                "address": "서울 용산구 공개로 1",
                "latitude": "37.53",
                "longitude": "126.93",
                "burgerStyle": "classic",
                "sourceType": "semas_kakao",
                "sourceAsOf": "2026-06-30",
                "publishDecision": "verified",
                "isActive": "true",
                "verifiedAt": "2026-08-01T10:00:00+09:00",
                "verificationNote": "사용자 승인",
            },
        ]
        self._write_csv(self.paths["publish"], publish[0].keys(), publish)
        styles = [
            {
                "storeId": row["storeId"],
                "candidateId": row["candidateId"],
                "name": row["name"],
                "address": row["address"],
                "proposedBurgerStyle": row["burgerStyle"],
                "reviewStatus": "approved",
            }
            for row in publish
        ]
        self._write_csv(self.paths["style"], styles[0].keys(), styles)
        staging = [
            {
                "candidateId": row["candidateId"],
                "displayName": row["name"],
                "address": row["address"],
                "latitude": row["latitude"],
                "longitude": row["longitude"],
                "stagingStatus": "candidate_pending",
                "sourceType": row["sourceType"],
                "sourceStoreId": "",
                "sourcePlaceId": "9001" if row["candidateId"] == "virtual_pending_b" else "",
                "placeUrl": "",
                "matchedCandidateId": "",
                "sourceCategory": "햄버거",
                "verificationStatus": "pending",
                "addressConflict": "",
                "provenanceNote": "가상 데이터",
            }
            for row in publish
        ]
        self._write_csv(self.paths["staging"], staging[0].keys(), staging)
        hold = [{
            "candidateId": "virtual_hold",
            "sourcePlaceId": "7001",
            "name": "가상 홀드 버거",
            "previousStatus": "needs_recheck",
            "stagingStatus": "hold_needs_recheck",
            "holdReason": "가상 주소 재검증 필요",
            "recommendedAction": "수동 확인",
        }]
        self._write_csv(self.paths["hold"], hold[0].keys(), hold)
        kakao = [{
            "discoveryId": "kakao_7001",
            "source": "kakao_local",
            "sourcePlaceId": "7001",
            "name": "가상 홀드 버거",
            "address": "서울 용산구 가상로 3",
            "latitude": "37.54",
            "longitude": "126.94",
        }]
        self._write_csv(self.paths["kakao"], kakao[0].keys(), kakao)
        candidate = [{
            "candidateId": "unused_candidate",
            "name": "가상 미사용",
            "address": "서울 용산구 가상로 4",
            "latitude": "37.55",
            "longitude": "126.95",
        }]
        self._write_csv(self.paths["candidate"], candidate[0].keys(), candidate)
        fixture = ROOT / "tests" / "fixtures" / "virtual_25_store_expansion_evidence.json"
        self.paths["evidence"].write_text(fixture.read_text(encoding="utf-8"), encoding="utf-8")

    def _build(self):
        with (
            patch.object(MODULE, "EXPECTED_PENDING", 2),
            patch.object(MODULE, "EXPECTED_HOLD", 1),
            patch.object(MODULE, "EXPECTED_PUBLIC", 1),
            patch.object(MODULE, "TARGET_PUBLIC_STORES", 5),
        ):
            return MODULE.build_25_store_expansion_review(
                self.paths["publish"],
                self.paths["style"],
                self.paths["staging"],
                self.paths["hold"],
                self.paths["kakao"],
                self.paths["candidate"],
                self.paths["evidence"],
                self.paths["output"],
            )

    def test_extracts_pending_and_hold_but_excludes_public(self):
        rows, summary = self._build()
        self.assertEqual(3, len(rows))
        self.assertEqual({"pending": 2, "hold": 1}, {"pending": summary["pending"], "hold": summary["hold"]})
        self.assertNotIn("virtual_public", {row["candidateId"] for row in rows})

    def test_review_item_ids_are_stable_and_not_row_numbers(self):
        first, _ = self._build()
        with self.paths["publish"].open(encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.DictReader(handle))
        self._write_csv(self.paths["publish"], rows[0].keys(), list(reversed(rows)))
        second, _ = self._build()
        first_ids = {row["candidateId"]: row["reviewItemId"] for row in first}
        second_ids = {row["candidateId"]: row["reviewItemId"] for row in second}
        self.assertEqual(first_ids, second_ids)
        self.assertTrue(all(value.startswith("p6b_") for value in first_ids.values()))

    def test_preserves_hold_reason_and_never_changes_states(self):
        rows, _ = self._build()
        hold = next(row for row in rows if row["sourceGroup"] == "hold")
        self.assertEqual("가상 주소 재검증 필요", hold["originalHoldReason"])
        self.assertTrue(all(row["currentIsActive"] == "false" for row in rows))
        self.assertFalse(any(row["currentPublishDecision"] in {"verified", "rejected"} for row in rows))

    def test_input_files_remain_unchanged(self):
        protected = [self.paths[key] for key in ("publish", "style", "staging", "hold", "kakao", "candidate")]
        before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in protected}
        self._build()
        after = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in protected}
        self.assertEqual(before, after)

    def test_rebuild_is_idempotent_and_preserves_reviewer_note(self):
        rows, _ = self._build()
        rows[0]["reviewerNote"] = "사람이 입력한 메모"
        self._write_csv(self.paths["output"], MODULE.OUTPUT_HEADERS, rows)
        rebuilt, _ = self._build()
        self.assertEqual("사람이 입력한 메모", rebuilt[0]["reviewerNote"])

    def test_identity_mismatch_is_rejected_even_when_name_matches(self):
        payload = json.loads(self.paths["evidence"].read_text(encoding="utf-8"))
        payload["items"][0]["candidateId"] = "wrong_candidate"
        self.paths["evidence"].write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        with self.assertRaises(MODULE.StorePublishingError):
            self._build()

    def test_address_mismatch_is_rejected(self):
        payload = json.loads(self.paths["evidence"].read_text(encoding="utf-8"))
        payload["items"][0]["address"] = "서울 용산구 다른로 99"
        self.paths["evidence"].write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        with self.assertRaises(MODULE.StorePublishingError):
            self._build()

    def test_weak_evidence_cannot_be_ready(self):
        payload = json.loads(self.paths["evidence"].read_text(encoding="utf-8"))
        payload["items"][0]["sources"] = payload["items"][0]["sources"][:1]
        payload["items"][0]["sources"][0]["currentOperationalSignal"] = False
        self.paths["evidence"].write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        with self.assertRaises(MODULE.StorePublishingError):
            self._build()

    def test_shortfall_is_calculated_from_safe_recommendations(self):
        _, summary = self._build()
        self.assertEqual(2, summary["recommended"])
        self.assertEqual(2, summary["shortfall"])

    def test_recommendation_limit_is_enforced(self):
        with (
            patch.object(MODULE, "EXPECTED_PENDING", 2),
            patch.object(MODULE, "EXPECTED_HOLD", 1),
            patch.object(MODULE, "EXPECTED_PUBLIC", 1),
            patch.object(MODULE, "MAX_RECOMMENDATIONS", 1),
        ):
            with self.assertRaises(MODULE.StorePublishingError):
                MODULE.build_25_store_expansion_review(
                    self.paths["publish"], self.paths["style"], self.paths["staging"],
                    self.paths["hold"], self.paths["kakao"], self.paths["candidate"],
                    self.paths["evidence"], self.paths["output"]
                )


if __name__ == "__main__":
    unittest.main()
