from __future__ import annotations

import csv
import uuid
from pathlib import Path
from typing import Mapping, Sequence


def make_style_review_rows(
    identities: Sequence[Mapping[str, str]],
    styles: Mapping[int, str],
    *,
    approved_numbers: set[int] | None = None,
) -> list[dict[str, str]]:
    approved_numbers = approved_numbers or set()
    rows: list[dict[str, str]] = []
    for index, identity in enumerate(identities, start=1):
        style = styles.get(index, "unclassified")
        has_proposal = style != "unclassified"
        approved = index in approved_numbers
        rows.append(
            {
                "reviewNumber": str(index),
                "storeId": identity.get("storeId")
                or str(uuid.UUID(int=index)),
                "candidateId": identity["candidateId"],
                "name": identity.get("name") or identity["displayName"],
                "address": identity["address"],
                "currentBurgerStyle": "unclassified",
                "proposedBurgerStyle": style,
                "reviewStatus": (
                    "approved" if approved else "proposed" if has_proposal else "needs_recheck"
                ),
                "confidence": "high" if has_proposal else "low",
                "evidenceSourceType": "official_website" if has_proposal else "",
                "evidenceSourceName": "합성 공식 메뉴" if has_proposal else "",
                "evidenceUrl": "https://example.invalid/menu" if has_proposal else "",
                "evidenceCheckedAt": "2026-08-20" if has_proposal else "",
                "evidenceNote": "합성 테스트 근거" if has_proposal else "근거 부족",
                "reviewerNote": "합성 사용자 승인" if approved else "",
                "secondaryEvidenceSourceType": "",
                "secondaryEvidenceSourceName": "",
                "secondaryEvidenceUrl": "",
                "sourceAgreement": "consistent" if has_proposal else "unavailable",
                "freshnessNote": "합성 테스트 확인일" if has_proposal else "",
                "approvalRecommendation": (
                    "ready_for_user_approval" if has_proposal else "needs_manual_check"
                ),
            }
        )
    return rows


def write_style_review(
    path: Path,
    headers: Sequence[str],
    rows: Sequence[Mapping[str, str]],
) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)
