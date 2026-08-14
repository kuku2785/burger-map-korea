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
    PROJECT_ROOT / "scripts" / "data" / "recheck_kakao_burger_addresses.py"
)

spec = importlib.util.spec_from_file_location("recheck_kakao_burger_addresses", SCRIPT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError(f"스크립트를 불러올 수 없습니다: {SCRIPT_PATH}")
recheck = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = recheck
spec.loader.exec_module(recheck)


def kakao_document(
    *,
    place_id: str,
    name: str,
    road_address: str,
    lot_address: str,
    latitude: str,
    longitude: str,
) -> dict[str, object]:
    return {
        "id": place_id,
        "place_name": name,
        "category_name": "음식점 > 양식 > 햄버거",
        "address_name": lot_address,
        "road_address_name": road_address,
        "x": longitude,
        "y": latitude,
        "place_url": f"https://place.map.kakao.com/{place_id}",
    }


class QueryFixtureTransport:
    def __init__(self, documents_by_query: dict[str, list[dict[str, object]]]) -> None:
        self.documents_by_query = documents_by_query
        self.calls: list[tuple[str, int, int]] = []

    def __call__(self, url: str, headers, timeout_seconds: float):
        del timeout_seconds
        self.assert_safe_headers(headers)
        parameters = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
        query = parameters["query"][0]
        page = int(parameters["page"][0])
        size = int(parameters["size"][0])
        self.calls.append((query, page, size))
        return {
            "documents": self.documents_by_query.get(query, []),
            "meta": {"is_end": True},
        }

    @staticmethod
    def assert_safe_headers(headers) -> None:
        if headers.get("Authorization") != "KakaoAK synthetic-secret-key":
            raise AssertionError("합성 API 키가 Authorization 헤더에만 있어야 합니다.")


class KakaoAddressRecheckTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.temp_path = Path(self.temporary_directory.name)
        self.input_path = self.temp_path / "reviewed.csv"
        self.output_path = self.temp_path / "address_recheck.csv"
        self.targets = (
            recheck.RecheckTarget(
                "다운타우너 한남",
                "OLD-DOWN",
                "서울 용산구 대사관로5길 12",
                "서울 용산구 이태원로42길 28-4",
                (
                    "다운타우너 한남",
                    "다운타우너 한남 새주소",
                    "다운타우너 한남 이전주소",
                ),
            ),
            recheck.RecheckTarget(
                "잭잭",
                "OLD-JACK",
                "서울 용산구 이태원로 134",
                "서울 용산구 회나무로6길 21",
                ("잭잭", "잭잭 새주소", "잭잭 이전주소"),
            ),
        )
        self.config = recheck.RecheckConfig(
            self.targets,
            longitude=126.9816,
            latitude=37.5326,
            radius_meters=12000,
        )
        self._write_reviewed_input()

    def _write_reviewed_input(self) -> None:
        fieldnames = (
            "sourcePlaceId",
            "name",
            "address",
            "manualReviewStatus",
            "manualReviewAction",
        )
        with self.input_path.open("w", encoding="utf-8-sig", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()
            for target in self.targets:
                writer.writerow(
                    {
                        "sourcePlaceId": target.previous_source_place_id,
                        "name": target.target_name,
                        "address": target.previous_address,
                        "manualReviewStatus": "needs_recheck",
                        "manualReviewAction": "needs_address_check",
                    }
                )

    def test_synthetic_config_contains_exactly_two_targets_and_six_queries(self) -> None:
        config_path = self.temp_path / "targets.json"
        config_path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "center": {
                        "longitude": self.config.longitude,
                        "latitude": self.config.latitude,
                        "radiusMeters": self.config.radius_meters,
                    },
                    "targets": [
                        {
                            "targetName": target.target_name,
                            "previousSourcePlaceId": target.previous_source_place_id,
                            "previousAddress": target.previous_address,
                            "expectedPublicAddress": target.expected_public_address,
                            "queries": list(target.queries),
                        }
                        for target in self.targets
                    ],
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        config = recheck.load_recheck_config(config_path)

        self.assertEqual(len(config.targets), 2)
        self.assertEqual(config.query_count, 6)
        self.assertEqual(
            tuple(query for target in config.targets for query in target.queries),
            tuple(query for target in self.targets for query in target.queries),
        )

    def run_recheck(self, documents_by_query):
        transport = QueryFixtureTransport(documents_by_query)
        client = recheck.KakaoKeywordClient(
            "synthetic-secret-key",
            transport=transport,
            max_api_calls=recheck.MAX_API_CALLS,
        )
        rows, call_count = recheck.recheck_addresses(
            client=client,
            config=self.config,
            input_path=self.input_path,
            output_path=self.output_path,
            checked_at="2026-08-13T00:00:00+00:00",
        )
        return rows, call_count, transport

    def test_preserves_all_old_and_new_results_and_uses_six_calls(self) -> None:
        old_downtown = kakao_document(
            place_id="OLD-DOWN",
            name="다운타우너 한남",
            road_address="서울 용산구 대사관로5길 12",
            lot_address="서울 용산구 한남동 1-1",
            latitude="37.5348",
            longitude="127.0008",
        )
        new_downtown = kakao_document(
            place_id="NEW-DOWN",
            name="다운타우너 한남점",
            road_address="서울 용산구 이태원로42길 28-4",
            lot_address="서울 용산구 한남동 2-2",
            latitude="37.5359",
            longitude="126.9961",
        )
        new_jack = kakao_document(
            place_id="NEW-JACK",
            name="잭잭 이태원점",
            road_address="서울 용산구 회나무로6길 21",
            lot_address="서울 용산구 이태원동 3-3",
            latitude="37.5390",
            longitude="126.9900",
        )
        documents = {
            self.targets[0].queries[0]: [old_downtown],
            self.targets[0].queries[1]: [new_downtown],
            self.targets[0].queries[2]: [old_downtown, new_downtown],
            self.targets[1].queries[0]: [new_jack],
            self.targets[1].queries[1]: [new_jack],
            self.targets[1].queries[2]: [new_jack],
        }
        input_hash_before = hashlib.sha256(self.input_path.read_bytes()).hexdigest()

        rows, call_count, transport = self.run_recheck(documents)

        input_hash_after = hashlib.sha256(self.input_path.read_bytes()).hexdigest()
        downtown_rows = [row for row in rows if row["targetName"] == "다운타우너 한남"]
        jack_rows = [row for row in rows if row["targetName"] == "잭잭"]
        self.assertEqual(call_count, 6)
        self.assertEqual(len(transport.calls), 6)
        self.assertTrue(all(page == 1 and size == 15 for _, page, size in transport.calls))
        self.assertEqual(
            {row["resultSourcePlaceId"] for row in downtown_rows},
            {"OLD-DOWN", "NEW-DOWN"},
        )
        self.assertEqual(
            {row["recheckDecision"] for row in downtown_rows},
            {"conflicting_results"},
        )
        self.assertEqual(
            {row["recheckDecision"] for row in jack_rows},
            {"resolved_new_place"},
        )
        self.assertEqual(input_hash_before, input_hash_after)
        self.assertEqual(tuple(rows[0]), recheck.OUTPUT_HEADERS)
        self.assertNotIn("synthetic-secret-key", self.output_path.read_text(encoding="utf-8-sig"))

    def test_non_yongsan_and_wrong_name_results_are_not_accepted(self) -> None:
        wrong_name = kakao_document(
            place_id="OTHER",
            name="다른 매장",
            road_address="서울 용산구 가상로 1",
            lot_address="서울 용산구 가상동 1",
            latitude="37.53",
            longitude="126.98",
        )
        outside_yongsan = kakao_document(
            place_id="OUTSIDE",
            name="잭잭",
            road_address="서울 마포구 가상로 1",
            lot_address="서울 마포구 가상동 1",
            latitude="37.55",
            longitude="126.91",
        )
        documents = {
            query: [wrong_name, outside_yongsan]
            for target in self.targets
            for query in target.queries
        }

        rows, _, _ = self.run_recheck(documents)

        self.assertEqual(len(rows), 6)
        self.assertTrue(all(not row["resultSourcePlaceId"] for row in rows))
        self.assertEqual({row["recheckDecision"] for row in rows}, {"no_result"})

    def test_same_place_id_with_different_coordinates_stays_conflicting(self) -> None:
        first = kakao_document(
            place_id="OLD-DOWN",
            name="다운타우너 한남",
            road_address="서울 용산구 대사관로5길 12",
            lot_address="서울 용산구 한남동 1-1",
            latitude="37.5348",
            longitude="127.0008",
        )
        moved = dict(first, y="37.5358", x="127.0018")
        documents = {
            query: [first if index == 0 else moved]
            for target in self.targets
            for index, query in enumerate(target.queries)
        }

        rows, _, _ = self.run_recheck(documents)

        downtown_rows = [row for row in rows if row["targetName"] == "다운타우너 한남"]
        self.assertEqual(
            {row["recheckDecision"] for row in downtown_rows},
            {"conflicting_results"},
        )


if __name__ == "__main__":
    unittest.main()
