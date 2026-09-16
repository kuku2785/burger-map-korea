#!/usr/bin/env python3
"""Verify release APK/AAB client configuration and development-data safety."""

from __future__ import annotations

import argparse
import base64
import json
import re
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


FORBIDDEN_STAGING_ASSET = "assets/dev/yongsan_burger_stores_staging.json"
ASSET_MANIFEST_NAMES = {"AssetManifest.bin", "AssetManifest.json"}
PUBLIC_CLIENT_CONFIG_PATTERNS: tuple[re.Pattern[bytes], ...] = (
    re.compile(rb"AIza[0-9A-Za-z_-]{35}"),
    re.compile(rb"https://[a-z0-9-]{15,}\.supabase\.co"),
    re.compile(rb"sb_publishable_[A-Za-z0-9_-]{8,}"),
)
SERVER_SECRET_PATTERNS: tuple[re.Pattern[bytes], ...] = (
    re.compile(rb"sb_secret_[A-Za-z0-9_-]{8,}"),
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
)
JWT_PATTERN = re.compile(
    rb"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"
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
    public_config_hits: int
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
        value = item.get("id")
        if isinstance(value, str) and value.strip():
            tokens.add(value.strip().encode("utf-8"))
    if not tokens:
        raise BundleVerificationError("검사할 staging 매장 ID가 없습니다.")
    return tuple(sorted(tokens))


def _jwt_role(candidate: bytes) -> str | None:
    try:
        payload = candidate.split(b".")[1]
        padding = b"=" * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload + padding))
    except (IndexError, ValueError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(claims, dict):
        return None
    role = claims.get("role")
    return role if isinstance(role, str) else None


def _secret_hit_count(content: bytes) -> int:
    pattern_hits = sum(
        len(pattern.findall(content)) for pattern in SERVER_SECRET_PATTERNS
    )
    jwt_hits = sum(
        _jwt_role(candidate) != "anon"
        for candidate in JWT_PATTERN.findall(content)
    )
    return pattern_hits + jwt_hits


def _public_config_hit_count(content: bytes) -> int:
    pattern_hits = sum(
        len(pattern.findall(content)) for pattern in PUBLIC_CLIENT_CONFIG_PATTERNS
    )
    anon_jwt_hits = sum(
        _jwt_role(candidate) == "anon" for candidate in JWT_PATTERN.findall(content)
    )
    return pattern_hits + anon_jwt_hits


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
    public_config_hits = 0
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
                secret_pattern_hits += _secret_hit_count(content)
                public_config_hits += _public_config_hit_count(content)
                for token in staging_tokens:
                    if token in content:
                        matched_staging_tokens.add(token)
    except zipfile.BadZipFile as error:
        raise BundleVerificationError("올바른 APK/AAB ZIP 파일이 아닙니다.") from error

    return BundleInspection(
        entry_count=len(entries),
        forbidden_entry_hits=forbidden_entry_hits,
        asset_manifest_hits=asset_manifest_hits,
        staging_value_hits=len(matched_staging_tokens),
        secret_pattern_hits=secret_pattern_hits,
        public_config_hits=public_config_hits,
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
            "publicClientConfigHits": inspection.public_config_hits,
            "safe": inspection.is_safe,
        },
        ensure_ascii=True,
        indent=2,
        sort_keys=True,
    )


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "release APK/AAB의 staging 데이터와 서버 비밀값을 검사하고 "
            "공개 모바일 설정은 값 노출 없이 집계합니다."
        )
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
