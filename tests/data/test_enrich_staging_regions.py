import sys
from pathlib import Path
from copy import deepcopy

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "data"))
from enrich_staging_regions import enrich


def fixture():
    asset = [
        {
            "id": "candidate-test",
            "name": "Fixture",
            "address": "서울 용산구 예시로 10",
            "latitude": 37.5,
            "longitude": 127.0,
            "burgerStyle": "classic",
            "verificationStatus": "pending",
        }
    ]
    evidence = [
        {
            "candidateId": "candidate-test",
            "name": "Fixture",
            "queryAddress": "서울특별시 용산구 예시로 10",
            "status": "exact_address_region_evidence",
            "totalCount": 1,
            "candidates": [
                {
                    "b_code": "1117010100",
                    "h_code": "1117051000",
                    "region_1depth_name": "서울",
                    "region_2depth_name": "용산구",
                    "region_3depth_name": "후암동",
                    "road_address_name": "서울 용산구 예시로 10",
                    "issueCodes": [],
                }
            ],
        }
    ]
    return asset, evidence


def test_only_region_is_added_without_changing_ids_styles_or_verification():
    asset, evidence = fixture()
    original = deepcopy(asset)
    result, review = enrich(asset, evidence)
    assert asset == original
    assert {
        key: value for key, value in result[0].items() if key != "region"
    } == original[0]
    assert result[0]["region"]["dongCode"] == "1117010100"
    assert review[0]["reason"] == "development_preview_only"


@pytest.mark.parametrize(
    "change", ["mismatch", "floor", "missing", "ri", "administrative", "label"]
)
def test_unsupported_or_mismatched_evidence_keeps_store_but_drops_stale_region(change):
    asset, evidence = fixture()
    asset[0]["region"] = {"old": "stale"}
    if change == "mismatch":
        evidence[0]["queryAddress"] += " 1층"
    if change == "floor":
        evidence[0]["status"] = "candidate_needs_review"
    if change == "missing":
        evidence = []
    if change == "ri":
        evidence[0]["candidates"][0]["b_code"] = "1117031021"
    if change == "administrative":
        evidence[0]["candidates"][0]["b_code"] = ""
    if change == "label":
        evidence[0]["candidates"][0]["region_3depth_name"] = ""
    result, review = enrich(asset, evidence)
    assert len(result) == 1 and result[0]["id"] == asset[0]["id"]
    assert "region" not in result[0]
    assert review[0]["reason"] != "development_preview_only"


def test_duplicate_ids_and_public_inputs_rejected():
    asset, evidence = fixture()
    for items, proofs in ((asset * 2, evidence), (asset, evidence * 2)):
        with pytest.raises(ValueError):
            enrich(items, proofs)
    asset[0]["verificationStatus"] = "verified"
    with pytest.raises(ValueError):
        enrich(asset, evidence)
