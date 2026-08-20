#!/usr/bin/env python3
"""Verify that a release APK/AAB excludes development staging data."""

from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


FORBIDDEN_STAGING_ASSET = "assets/dev/yongsan_burger_stores_staging.json"
ASSET_MANIFEST_NAMES = {"AssetManifest.bin", "AssetManifest.json"}
SECRET_PATTERNS = (
    re.compile(rb"AIza[0-9A-Za-z_-]{35}"),
    re.compile(
        rb"eyJ[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}\."
        rb"[0-9A-Za-z_-]{10,}"
    ),
    re.compile(rb"https://[a-z0-9]{15,}\.supabase\.co"),
    re.compile(rb"sb_(?:publishable|secret)_[0-9A-Za-z_-]{20,}"),
)


class BundleVerificationError(ValueError):
    """Raised when the requested artifact cannot be inspected safely."""


@dataclass(frozen=True)
class BundleInspection:
    entry_count: int
    forbidden_entry_hits: int
    asset_manifest_hits: int
    staging_value_hits: int
    secret_pattern_hits: int
    staging_values_checked: int

    @property
    def is_safe(self) -> bool:
        return (
            self.forbidden_entry_hits == 0
            and self.asset_manifest_hits == 0
            and self.staging_value_hits == 0
            and self.secret_pattern_hits == 0
        )


def _read_staging_tokens(path: Path | None) -> tuple[bytes, ...]:
    if path is None:
        return ()
    if not path.is_file():
        raise BundleVerificationError("staging JSON 파일을 찾을 수 없습니다.")
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise BundleVerificationError("staging JSON을 읽을 수 없습니다.") from error
    if not isinstance(decoded, list):
        raise BundleVerificationError("staging JSON 최상위 값이 배열이 아닙니다.")

    tokens: set[bytes] = set()
    for item in decoded:
        if not isinstance(item, dict):
            raise BundleVerificationError("staging JSON 행 형식이 올바르지 않습니다.")
        for field in ("id", "name", "address"):
            value = item.get(field)
            if isinstance(value, str) and value.strip():
                token = value.strip().encode("utf-8")
                if field == "id" or len(token) >= 6:
                    tokens.add(token)
    if not tokens:
        raise BundleVerificationError("검사할 staging 식별 값이 없습니다.")
    return tuple(sorted(tokens))


def _secret_hit_count(content: bytes) -> int:
    return sum(len(pattern.findall(content)) for pattern in SECRET_PATTERNS)


def inspect_release_bundle(
    bundle_path: Path,
    *,
    staging_json_path: Path | None = None,
) -> BundleInspection:
    if not bundle_path.is_file():
        raise BundleVerificationError("release bundle 파일을 찾을 수 없습니다.")
    staging_tokens = _read_staging_tokens(staging_json_path)
    forbidden_path = FORBIDDEN_STAGING_ASSET.encode("utf-8")
    forbidden_entry_hits = 0
    asset_manifest_hits = 0
    secret_pattern_hits = 0
    matched_staging_tokens: set[bytes] = set()

    try:
        with zipfile.ZipFile(bundle_path) as bundle:
            entries = bundle.infolist()
            if not entries:
                raise BundleVerificationError("release bundle ZIP이 비어 있습니다.")
            for entry in entries:
                normalized_name = entry.filename.replace("\\", "/")
                if FORBIDDEN_STAGING_ASSET in normalized_name:
                    forbidden_entry_hits += 1
                if entry.is_dir():
                    continue
                try:
                    content = bundle.read(entry)
                except (OSError, RuntimeError, zipfile.BadZipFile) as error:
                    raise BundleVerificationError(
                        "release bundle entry를 읽을 수 없습니다."
                    ) from error
                if Path(normalized_name).name in ASSET_MANIFEST_NAMES:
                    if forbidden_path in content:
                        asset_manifest_hits += 1
                for token in staging_tokens:
                    if token in content:
                        matched_staging_tokens.add(token)
                secret_pattern_hits += _secret_hit_count(content)
    except zipfile.BadZipFile as error:
        raise BundleVerificationError("올바른 APK/AAB ZIP 파일이 아닙니다.") from error

    return BundleInspection(
        entry_count=len(entries),
        forbidden_entry_hits=forbidden_entry_hits,
        asset_manifest_hits=asset_manifest_hits,
        staging_value_hits=len(matched_staging_tokens),
        secret_pattern_hits=secret_pattern_hits,
        staging_values_checked=len(staging_tokens),
    )


def format_summary(inspection: BundleInspection) -> str:
    return json.dumps(
        {
            "entryCount": inspection.entry_count,
            "forbiddenStagingEntryHits": inspection.forbidden_entry_hits,
            "assetManifestStagingHits": inspection.asset_manifest_hits,
            "stagingValueHits": inspection.staging_value_hits,
            "stagingValuesChecked": inspection.staging_values_checked,
            "secretPatternHits": inspection.secret_pattern_hits,
            "safe": inspection.is_safe,
        },
        ensure_ascii=True,
        indent=2,
        sort_keys=True,
    )


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="release APK/AAB에서 개발용 staging 데이터와 키를 검사합니다."
    )
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--staging-json", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        inspection = inspect_release_bundle(
            args.bundle,
            staging_json_path=args.staging_json,
        )
    except BundleVerificationError as error:
        print(f"verification_error={error}", file=sys.stderr)
        return 2

    print(format_summary(inspection))
    if not inspection.is_safe:
        print("verification_result=failed", file=sys.stderr)
        return 1
    print("verification_result=passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
