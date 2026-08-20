#!/usr/bin/env python3
"""Generate an offline SQL update for approved styles of published stores."""

from __future__ import annotations

import argparse
import json
import re
import sys
import uuid
from pathlib import Path
from typing import Mapping, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from build_burger_style_review import (  # noqa: E402
    ALLOWED_STYLES,
    DEFAULT_OUTPUT_PATH as DEFAULT_STYLE_REVIEW_PATH,
    read_validated_style_review_rows,
)
from store_publishing_common import (  # noqa: E402
    REVIEW_HEADERS,
    StorePublishingError,
    normalize_store_text,
    read_csv_rows,
)


PROJECT_ROOT = SCRIPT_DIR.parents[1]
DEFAULT_PUBLISH_REVIEW_PATH = (
    PROJECT_ROOT / "data" / "review" / "yongsan_burger_store_publish_review.csv"
)
DEFAULT_OUTPUT_PATH = (
    PROJECT_ROOT / "data" / "staging" / "yongsan_burger_style_update.sql"
)
FORBIDDEN_SQL_PATTERNS = {
    "INSERT": re.compile(r"\binsert\b", re.IGNORECASE),
    "DELETE": re.compile(r"\bdelete\b", re.IGNORECASE),
    "UPSERT": re.compile(r"\bupsert\b", re.IGNORECASE),
    "RPC": re.compile(r"\brpc\b", re.IGNORECASE),
    "candidateId": re.compile(r"candidateId", re.IGNORECASE),
    "external Place ID": re.compile(
        r"(?:source_place_id|place_url|kakao_place_id|google_place_id)",
        re.IGNORECASE,
    ),
    "URL": re.compile(r"https?://", re.IGNORECASE),
    "key": re.compile(
        r"(?:sb_(?:publishable|secret)_[A-Za-z0-9_-]{20,}|"
        r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)"
    ),
}


class NoStyleUpdatesError(StorePublishingError):
    """Raised when no approved style belongs to a verified active store."""


def _parse_boolean(value: str, candidate_id: str) -> bool:
    normalized = value.strip().lower()
    if normalized not in {"true", "false"}:
        raise StorePublishingError(
            f"isActive는 true 또는 false여야 합니다: {candidate_id}"
        )
    return normalized == "true"


def build_style_update_targets(
    style_rows: Sequence[Mapping[str, str]],
    publish_rows: Sequence[Mapping[str, str]],
) -> list[dict[str, str]]:
    publish_by_candidate: dict[str, Mapping[str, str]] = {}
    seen_publish_store_ids: set[str] = set()
    for publish_row in publish_rows:
        candidate_id = publish_row.get("candidateId", "").strip()
        if not candidate_id or candidate_id in publish_by_candidate:
            raise StorePublishingError(
                f"게시 검수표 candidateId가 비었거나 중복됐습니다: {candidate_id}"
            )
        try:
            store_id = str(uuid.UUID(publish_row.get("storeId", "").strip()))
        except ValueError:
            raise StorePublishingError(
                f"게시 검수표 storeId가 UUID가 아닙니다: {candidate_id}"
            ) from None
        if store_id in seen_publish_store_ids:
            raise StorePublishingError(f"게시 검수표 storeId가 중복됐습니다: {candidate_id}")
        seen_publish_store_ids.add(store_id)
        publish_by_candidate[candidate_id] = publish_row

    style_ids = {row.get("candidateId", "").strip() for row in style_rows}
    if style_ids != set(publish_by_candidate):
        raise StorePublishingError("스타일 검수표와 게시 검수표 candidateId 집합이 다릅니다.")

    targets: list[dict[str, str]] = []
    seen_target_ids: set[str] = set()
    for style_row in style_rows:
        candidate_id = style_row.get("candidateId", "").strip()
        publish_row = publish_by_candidate[candidate_id]
        style_store_id = str(uuid.UUID(style_row.get("storeId", "").strip()))
        publish_store_id = str(uuid.UUID(publish_row.get("storeId", "").strip()))
        mismatched = (["storeId"] if style_store_id != publish_store_id else []) + [
            field
            for field in ("name", "address")
            if normalize_store_text(style_row.get(field, ""))
            != normalize_store_text(publish_row.get(field, ""))
        ]
        if mismatched:
            raise StorePublishingError(
                f"스타일 검수표와 게시 검수표가 다릅니다: "
                f"{candidate_id}, {mismatched}"
            )

        is_active = _parse_boolean(publish_row.get("isActive", ""), candidate_id)
        publish_decision = publish_row.get("publishDecision", "").strip()
        if publish_decision != "verified" and is_active:
            raise StorePublishingError(
                f"verified가 아닌 게시 행은 활성화할 수 없습니다: {candidate_id}"
            )
        if style_row.get("reviewStatus", "").strip() != "approved":
            continue
        if publish_decision != "verified" or not is_active:
            continue

        style = style_row.get("proposedBurgerStyle", "").strip()
        if style not in ALLOWED_STYLES or style == "unclassified":
            raise StorePublishingError(
                f"승인 스타일이 올바르지 않습니다: {candidate_id}, {style}"
            )
        store_id = str(uuid.UUID(publish_row.get("storeId", "").strip()))
        if store_id in seen_target_ids:
            raise StorePublishingError(f"스타일 UPDATE 대상이 중복됐습니다: {store_id}")
        seen_target_ids.add(store_id)
        targets.append({"id": store_id, "burger_style": style})
    return targets


def _sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def build_style_update_sql(targets: Sequence[Mapping[str, str]]) -> str:
    if not targets:
        raise NoStyleUpdatesError(
            "approved 스타일과 verified+active 게시 상태가 일치하는 매장이 없습니다."
        )
    blocks: list[str] = []
    for target in targets:
        store_id = str(uuid.UUID(target["id"]))
        style = target["burger_style"]
        if style not in ALLOWED_STYLES or style == "unclassified":
            raise StorePublishingError(f"UPDATE 스타일이 올바르지 않습니다: {style}")
        blocks.append(
            "do $burger_map$\n"
            "declare\n"
            "  affected_rows integer;\n"
            "begin\n"
            "  update public.stores\n"
            f"  set burger_style = {_sql_text(style)}\n"
            f"  where id = {_sql_text(store_id)}::uuid\n"
            "    and verification_status = 'verified'\n"
            "    and is_active = true;\n\n"
            "  get diagnostics affected_rows = row_count;\n"
            "  if affected_rows <> 1 then\n"
            "    raise exception 'expected exactly one verified active store row';\n"
            "  end if;\n"
            "end\n"
            "$burger_map$;"
        )
    sql = "begin;\n\n" + "\n\n".join(blocks) + "\n\ncommit;\n"
    for label, pattern in FORBIDDEN_SQL_PATTERNS.items():
        if pattern.search(sql):
            raise StorePublishingError(f"생성 SQL에 금지 값이 포함됐습니다: {label}")
    return sql


def generate_style_update_sql(
    style_review_path: Path,
    publish_review_path: Path,
    output_path: Path,
    *,
    overwrite: bool = False,
) -> int:
    if output_path.exists() and not overwrite:
        raise StorePublishingError(f"출력 SQL이 이미 존재합니다: {output_path}")
    style_rows = read_validated_style_review_rows(style_review_path)
    headers, publish_rows = read_csv_rows(publish_review_path, set(REVIEW_HEADERS))
    if headers != list(REVIEW_HEADERS):
        raise StorePublishingError("게시 검수표 컬럼 또는 순서가 다릅니다.")
    targets = build_style_update_targets(style_rows, publish_rows)
    sql = build_style_update_sql(targets)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_name(f".{output_path.name}.tmp")
    try:
        temporary_path.write_text(sql, encoding="utf-8")
        temporary_path.replace(output_path)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise StorePublishingError(
            f"스타일 UPDATE SQL을 저장할 수 없습니다: {output_path}"
        ) from error
    return len(targets)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="승인 스타일을 게시된 verified+active 매장에 반영할 UPDATE SQL을 생성합니다."
    )
    parser.add_argument("--style-review", type=Path, default=DEFAULT_STYLE_REVIEW_PATH)
    parser.add_argument(
        "--publish-review",
        type=Path,
        default=DEFAULT_PUBLISH_REVIEW_PATH,
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        generated_rows = generate_style_update_sql(
            args.style_review,
            args.publish_review,
            args.output,
            overwrite=args.overwrite,
        )
        print(
            json.dumps(
                {
                    "generatedRows": generated_rows,
                    "outputPath": str(args.output.resolve()),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except NoStyleUpdatesError as error:
        print(f"안전 중단: {error}")
        return 3
    except StorePublishingError as error:
        print(f"오류: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
