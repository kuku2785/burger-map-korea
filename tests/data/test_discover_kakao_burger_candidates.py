from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
import urllib.parse
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = (
    PROJECT_ROOT / "scripts" / "data" / "discover_kakao_burger_candidates.py"
)
FIXTURE_PATH = PROJECT_ROOT / "tests" / "fixtures" / "kakao_keyword_pages.json"

spec = importlib.util.spec_from_file_location(
    "discover_kakao_burger_candidates", SCRIPT_PATH
)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
discovery = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = discovery
spec.loader.exec_module(discovery)


class FixtureTransport:
    def __init__(self, fixture_path: Path) -> None:
        self.pages = json.loads(fixture_path.read_text(encoding="utf-8-sig"))
        self.calls: list[tuple[str, int]] = []

    def __call__(self, url: str, headers, timeout_seconds: float):
        del headers, timeout_seconds
        parameters = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
        query = parameters["query"][0]
        page = int(parameters["page"][0])
        self.calls.append((query, page))
        return self.pages[query][str(page)]


class KakaoDiscoveryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temp_path = Path(self.temporary_directory.name)
        self.v2_path = self.temp_path / "v2.csv"
        self.reviewed_path = self.temp_path / "reviewed.csv"
        self.output_path = self.temp_path / "discovery.csv"
        self._write_existing_csv(self.v2_path, "pending")
        self._write_existing_csv(self.reviewed_path, "rejected")
        self.transport = FixtureTransport(FIXTURE_PATH)
        self.config = discovery.SearchConfig(
            queries=("용산구 수제버거", "이태원 수제버거"),
            longitude=126.9816,
            latitude=37.5326,
            radius_meters=12000,
        )

    @staticmethod
    def _write_existing_csv(path: Path, status: str) -> None:
        fieldnames = (
            "candidateId",
            "name",
            "address",
            "latitude",
            "longitude",
            "verificationStatus",
        )
        with path.open("w", encoding="utf-8-sig", newline="") as output_file:
            writer = csv.DictWriter(output_file, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerow(
                {
                    "candidateId": "semas_SYNTHETIC001",
                    "name": "가상버거",
                    "address": "서울 용산구 가상로 1",
                    "latitude": "37.5300",
                    "longitude": "126.9800",
                    "verificationStatus": status,
                }
            )

    def run_discovery(self):
        client = discovery.KakaoKeywordClient(
            "synthetic-secret-key",
            transport=self.transport,
            max_api_calls=10,
        )
        rows, stats = discovery.discover(
            client=client,
            config=self.config,
            v2_path=self.v2_path,
            reviewed_path=self.reviewed_path,
            output_path=self.output_path,
            discovered_at="2026-08-13T00:00:00+00:00",
        )
        return rows, stats

    @staticmethod
    def row_by_place_id(rows: list[dict[str, str]], place_id: str):
        return next(row for row in rows if row["sourcePlaceId"] == place_id)

    def test_missing_api_key_fails_safely(self) -> None:
        env_path = self.temp_path / ".env"
        env_path.write_text("OTHER_KEY=value\n", encoding="utf-8")

        with self.assertRaises(discovery.MissingApiKeyError) as context:
            discovery.read_kakao_api_key(env_path, environ={})

        self.assertIn("KAKAO_REST_API_KEY", str(context.exception))
        self.assertNotIn("value", str(context.exception))

    def test_api_key_never_appears_in_error(self) -> None:
        secret = "do-not-print-this-secret"

        def failing_transport(url, headers, timeout_seconds):
            del url, headers, timeout_seconds
            raise discovery.KakaoApiError("합성 네트워크 오류")

        client = discovery.KakaoKeywordClient(secret, transport=failing_transport)
        with self.assertRaises(discovery.KakaoApiError) as context:
            client.search_all(
                "용산구 수제버거",
                longitude=126.98,
                latitude=37.53,
                radius_meters=12000,
            )

        self.assertNotIn(secret, str(context.exception))

    def test_filters_out_non_yongsan_and_exclusion_rules(self) -> None:
        rows, stats = self.run_discovery()
        place_ids = {row["sourcePlaceId"] for row in rows}

        self.assertNotIn("K002", place_ids)
        self.assertNotIn("K003", place_ids)
        self.assertNotIn("K007", place_ids)
        self.assertNotIn("K008", place_ids)
        self.assertEqual(stats.excluded_by_rule["large_fast_food_chain"], 1)
        self.assertEqual(stats.excluded_by_rule["pizza_specialty"], 1)
        self.assertEqual(stats.excluded_by_rule["rice_burger"], 1)

    def test_generic_pizza_category_and_known_large_chain_are_excluded(self) -> None:
        rules = discovery.load_exclusion_rules(
            discovery.DEFAULT_EXCLUSION_RULES_PATH
        )

        pizza_reasons = discovery.match_exclusion_rules(
            {
                "상호명": "가상화덕연구소",
                "sourceCategory": "음식점 > 양식 > 피자",
            },
            rules,
        )
        chain_reasons = discovery.match_exclusion_rules(
            {
                "상호명": "KFC 가상점",
                "sourceCategory": "음식점 > 패스트푸드 > KFC",
            },
            rules,
        )

        self.assertIn("pizza_specialty", pizza_reasons)
        self.assertIn("large_fast_food_chain", chain_reasons)

    def test_same_place_id_merges_matched_queries_without_duplicates(self) -> None:
        rows, stats = self.run_discovery()
        candidate = self.row_by_place_id(rows, "K001")
        matched_queries = json.loads(candidate["matchedQueries"])

        self.assertEqual(rows.count(candidate), 1)
        self.assertEqual(
            matched_queries, ["용산구 수제버거", "이태원 수제버거"]
        )
        self.assertEqual(stats.deduplicated_places, 4)

    def test_existing_name_and_address_match_uses_candidate_id(self) -> None:
        rows, _ = self.run_discovery()
        candidate = self.row_by_place_id(rows, "K001")

        self.assertEqual(candidate["matchStatus"], "existing_match")
        self.assertEqual(candidate["matchedCandidateId"], "semas_SYNTHETIC001")

    def test_coordinate_only_nearby_result_is_possible_duplicate(self) -> None:
        rows, _ = self.run_discovery()
        candidate = self.row_by_place_id(rows, "K005")

        self.assertEqual(candidate["matchStatus"], "possible_duplicate")
        self.assertEqual(candidate["screeningStatus"], "needs_recheck")

    def test_new_place_is_new_candidate_and_never_verified(self) -> None:
        rows, _ = self.run_discovery()
        clear_candidate = self.row_by_place_id(rows, "K006")
        ambiguous_candidate = self.row_by_place_id(rows, "K004")

        self.assertEqual(clear_candidate["matchStatus"], "new_candidate")
        self.assertEqual(clear_candidate["screeningStatus"], "pending")
        self.assertEqual(ambiguous_candidate["matchStatus"], "new_candidate")
        self.assertEqual(ambiguous_candidate["screeningStatus"], "needs_recheck")
        self.assertIn("ambiguous_category", ambiguous_candidate["screeningFlags"])
        self.assertTrue(
            all(row["screeningStatus"] != "verified" for row in rows)
        )

    def test_reviewed_conflict_is_flagged_without_modifying_reviewed(self) -> None:
        before_hash = hashlib.sha256(self.reviewed_path.read_bytes()).hexdigest()
        rows, stats = self.run_discovery()
        after_hash = hashlib.sha256(self.reviewed_path.read_bytes()).hexdigest()
        candidate = self.row_by_place_id(rows, "K001")

        self.assertEqual(before_hash, after_hash)
        self.assertEqual(candidate["conflictWithReviewed"], "true")
        self.assertIn("conflict_with_reviewed", candidate["screeningFlags"])
        self.assertEqual(stats.conflict_with_reviewed, 1)

    def test_pagination_stops_at_is_end(self) -> None:
        self.run_discovery()

        self.assertEqual(
            self.transport.calls,
            [
                ("용산구 수제버거", 1),
                ("용산구 수제버거", 2),
                ("이태원 수제버거", 1),
            ],
        )

    def test_429_is_not_retried(self) -> None:
        calls = 0

        def rate_limited_transport(url, headers, timeout_seconds):
            nonlocal calls
            del url, headers, timeout_seconds
            calls += 1
            raise discovery.KakaoApiError(
                "카카오 API 쿼터 또는 요청 한도에 도달했습니다(HTTP 429). 재시도하지 않았습니다."
            )

        client = discovery.KakaoKeywordClient(
            "synthetic-secret-key", transport=rate_limited_transport
        )
        with self.assertRaises(discovery.KakaoApiError):
            client.search_all(
                "용산구 수제버거",
                longitude=126.98,
                latitude=37.53,
                radius_meters=12000,
            )

        self.assertEqual(calls, 1)
        self.assertEqual(client.call_count, 1)


if __name__ == "__main__":
    unittest.main()
