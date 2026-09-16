"""Evidence collection must not turn uncertainty or request errors into approval."""

from __future__ import annotations

import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlparse

SCRIPT_DIR = Path(__file__).resolve().parents[2] / "scripts" / "data"
sys.path.insert(0, str(SCRIPT_DIR))

from collect_store_region_evidence import (  # noqa: E402
    API_URL,
    RegionAuditError,
    collect_evidence,
    extract_evidence,
)


def response(*, road="서울 용산구 예시로 10", total=1):
    documents = (
        []
        if total == 0
        else [
            {
                "x": "STORE_LONGITUDE_NOT_RETAINED",
                "y": "STORE_LATITUDE_NOT_RETAINED",
                "unrecognized": "NOT_RETAINED",
                "address": {
                    "address_name": "서울 용산구 예시동 1",
                    "region_1depth_name": "서울",
                    "region_2depth_name": "용산구",
                    "region_3depth_name": "법정예시동",
                    "region_3depth_h_name": "행정예시동",
                    "b_code": "1117010100",
                    "h_code": "1117051000",
                    "x": "NOT_RETAINED",
                },
                "road_address": {"address_name": road, "y": "NOT_RETAINED"},
            }
        ]
    )
    return {
        "meta": {"total_count": total, "pageable_count": total, "is_end": True},
        "documents": documents,
    }


class ExtractEvidenceTests(unittest.TestCase):
    def test_exact_address_keeps_legal_admin_separate_without_approving_store(self):
        result = extract_evidence("서울특별시  용산구 예시로 10", response())
        self.assertEqual(result["status"], "exact_address_region_evidence")
        self.assertTrue(result["manualReviewRequired"])
        self.assertFalse(result["storeExistenceVerified"])
        self.assertEqual(result["candidates"][0]["region_3depth_name"], "법정예시동")
        self.assertEqual(result["candidates"][0]["region_3depth_h_name"], "행정예시동")
        self.assertNotIn("NOT_RETAINED", json.dumps(result))

    def test_floor_and_hyphen_differences_require_review(self):
        for query in ("서울 용산구 예시로 10 1층", "서울 용산구 예시로 1-0"):
            with self.subTest(query=query):
                result = extract_evidence(query, response())
                self.assertEqual(result["status"], "candidate_needs_review")
                self.assertIn(
                    "ADDRESS_NOT_EXACT", result["candidates"][0]["issueCodes"]
                )

    def test_valid_zero_is_distinct_from_malformed_response(self):
        self.assertEqual(
            extract_evidence("주소", response(total=0))["status"], "no_result"
        )
        for invalid in (
            {},
            {"meta": {}, "documents": []},
            {
                "meta": {"total_count": 0, "pageable_count": 0, "is_end": False},
                "documents": [],
            },
        ):
            with self.subTest(response=invalid), self.assertRaises(RegionAuditError):
                extract_evidence("주소", invalid)

    def test_multiple_and_partial_results_never_pick_first_as_exact(self):
        multiple = response(total=2)
        multiple["documents"].append(response()["documents"][0])
        partial = response(total=2)
        partial["meta"]["is_end"] = False
        for value in (multiple, partial):
            with self.subTest(response=value):
                result = extract_evidence("서울 용산구 예시로 10", value)
                self.assertEqual(result["status"], "ambiguous_or_partial")
                self.assertEqual(result["returnedCount"], len(value["documents"]))

    def test_missing_and_invalid_region_codes_do_not_become_complete(self):
        value = response()
        value["documents"][0]["address"]["h_code"] = ""
        result = extract_evidence("서울 용산구 예시로 10", value)
        self.assertEqual(result["status"], "candidate_needs_review")
        self.assertIn(
            "REGION_EVIDENCE_INCOMPLETE", result["candidates"][0]["issueCodes"]
        )
        self.assertIn("REGION_CODE_INVALID", result["candidates"][0]["issueCodes"])

    def test_malformed_candidate_does_not_get_silently_dropped(self):
        value = response()
        value["documents"] = [None]
        with self.assertRaises(RegionAuditError):
            extract_evidence("주소", value)


class CollectEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.publish = self.root / "publish.csv"
        self.output = self.root / "new_evidence"
        self.rows = [
            {
                "storeId": f"10000000-0000-4000-8000-{index:012}",
                "candidateId": f"candidate_{index}",
                "name": f"Fixture {index}",
                "address": "서울 용산구 예시로 10",
                "burgerStyle": "classic",
                "publishDecision": "verified",
                "isActive": "true",
            }
            for index in range(1, 4)
        ]
        self.rows[-1]["publishDecision"] = "pending"
        self.write_rows()

    def write_rows(self):
        with self.publish.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=self.rows[0].keys())
            writer.writeheader()
            writer.writerows(self.rows)

    def test_only_approved_addresses_sent_and_original_uuids_and_files_preserved(self):
        before = self.publish.read_bytes()
        calls = []

        def transport(url, headers, timeout):
            calls.append(url)
            parsed = urlparse(url)
            self.assertEqual(f"{parsed.scheme}://{parsed.netloc}{parsed.path}", API_URL)
            self.assertEqual(
                parse_qs(parsed.query),
                {"query": ["서울 용산구 예시로 10"], "analyze_type": ["exact"], "size": ["10"]},
            )
            self.assertEqual(timeout, 10)
            return response()

        summary = collect_evidence(
            self.publish, self.output, "test-key-only", transport=transport
        )
        self.assertEqual(len(calls), 2)
        self.assertTrue(summary["completed"])
        self.assertFalse(summary["publishReady"])
        self.assertEqual(self.publish.read_bytes(), before)
        artifact = (self.output / "region_evidence.jsonl").read_text(encoding="utf-8")
        rows = [json.loads(line) for line in artifact.splitlines()]
        self.assertEqual(
            [row["storeId"] for row in rows], [row["storeId"] for row in self.rows[:2]]
        )
        self.assertNotIn("test-key-only", artifact)
        self.assertNotIn("NOT_RETAINED", artifact)

    def test_error_aborts_subsequent_reads_and_preserves_failure_as_failure(self):
        calls = []

        def failing(url, headers, timeout):
            calls.append(url)
            raise OSError("secret-error-not-for-output")

        summary = collect_evidence(
            self.publish, self.output, "fake-key", transport=failing
        )
        self.assertEqual(len(calls), 1)
        self.assertFalse(summary["completed"])
        self.assertEqual(
            summary["statusCounts"],
            {"request_or_response_error": 1, "not_attempted_after_error": 1},
        )
        artifact = (self.output / "region_evidence.jsonl").read_text(encoding="utf-8")
        self.assertNotIn("secret-error", artifact)
        self.assertNotIn("fake-key", artifact)
        self.assertEqual(len(artifact.splitlines()), 2)
        self.assertEqual(
            json.loads(artifact.splitlines()[0])["failureKind"], "api_or_network"
        )

    def test_existing_directory_and_request_limit_block_network_calls(self):
        def forbidden(*args):
            self.fail("request should not be sent")

        for limit in (0, 1, 26):
            with self.subTest(limit=limit), self.assertRaises(RegionAuditError):
                collect_evidence(
                    self.publish,
                    self.output,
                    "fake",
                    max_requests=limit,
                    transport=forbidden,
                )
        self.assertFalse(self.output.exists())
        self.output.mkdir()
        protected = self.output / "region_evidence.jsonl"
        protected.write_text("USER-OWNED", encoding="utf-8")
        with self.assertRaises(RegionAuditError):
            collect_evidence(self.publish, self.output, "fake", transport=forbidden)
        self.assertEqual(protected.read_text(encoding="utf-8"), "USER-OWNED")


if __name__ == "__main__":
    unittest.main()
