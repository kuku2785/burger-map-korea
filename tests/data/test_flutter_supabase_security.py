from __future__ import annotations

import re
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
LOADER_PATH = (
    PROJECT_ROOT
    / "lib"
    / "features"
    / "stores"
    / "data"
    / "supabase_store_locations_loader.dart"
)
CONFIG_PATH = PROJECT_ROOT / "lib" / "core" / "config" / "app_config.dart"
MAIN_PATH = PROJECT_ROOT / "lib" / "main.dart"
ENV_EXAMPLE_PATH = PROJECT_ROOT / ".env.example"


class FlutterSupabaseSecurityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.loader = LOADER_PATH.read_text(encoding="utf-8")
        cls.normalized_loader = re.sub(r"\s+", " ", cls.loader)
        cls.config = CONFIG_PATH.read_text(encoding="utf-8")
        cls.main = MAIN_PATH.read_text(encoding="utf-8")
        cls.env_example = ENV_EXAMPLE_PATH.read_text(encoding="utf-8")

    def test_loader_uses_verified_active_select_only(self) -> None:
        self.assertIn(".from('stores')", self.normalized_loader)
        self.assertIn(".select(supabaseStoreSelectColumns)", self.normalized_loader)
        self.assertIn(
            ".eq('verification_status', supabasePublicVerificationStatus)",
            self.normalized_loader,
        )
        self.assertIn(
            ".eq('is_active', supabasePublicIsActive)",
            self.normalized_loader,
        )
        self.assertIn(
            ".order(supabaseStoreOrderColumn, ascending: true)",
            self.normalized_loader,
        )
        self.assertIn("const supabasePublicVerificationStatus = 'verified'", self.loader)
        self.assertIn("const supabasePublicIsActive = true", self.loader)

    def test_loader_selects_only_allowed_columns(self) -> None:
        self.assertIn(
            "'id,name,address,latitude,longitude,burger_style,verification_status'",
            self.loader,
        )

    def test_loader_has_no_write_operations(self) -> None:
        for operation in ("insert", "update", "delete", "upsert", "rpc"):
            self.assertIsNone(
                re.search(rf"\.{operation}\s*\(", self.loader),
                operation,
            )

    def test_only_public_supabase_dart_defines_exist(self) -> None:
        combined = "\n".join((self.config, self.main, self.env_example))
        self.assertIn("SUPABASE_URL", combined)
        self.assertIn("SUPABASE_PUBLISHABLE_KEY", combined)
        for forbidden in (
            "SUPABASE_SECRET_KEY",
            "SUPABASE_SERVICE_ROLE_KEY",
            "DB_PASSWORD",
            "DATABASE_URL",
        ):
            self.assertNotIn(forbidden, combined)

    def test_initialization_is_guarded_by_mode_and_configuration(self) -> None:
        normalized_main = re.sub(r"\s+", " ", self.main)
        self.assertIn(
            "config.usesSupabaseStoreData && config.hasSupabaseConfiguration",
            normalized_main,
        )
        normalized_config = re.sub(r"\s+", " ", self.config)
        self.assertRegex(
            normalized_config,
            r"usesSupabaseStoreData\s*=>\s*!kReleaseMode\s*&&.*?"
            r"environment\s*==\s*AppEnvironment\.development\s*&&.*?"
            r"storeDataMode\s*==\s*StoreDataMode\.supabase",
        )
        self.assertIn("Supabase.initialize(", self.loader)
        self.assertIn("publishableKey: publishableKey.trim()", self.loader)
        self.assertNotIn("anonKey:", self.loader)

    def test_debug_diagnostics_do_not_print_sensitive_values(self) -> None:
        self.assertIn("enableDebugDiagnostics && kDebugMode", self.loader)
        self.assertIn("stage=${stage.name}", self.loader)
        self.assertIn("type=${_safeTypeName(error)}", self.loader)
        self.assertIn("code=$code", self.loader)
        self.assertIn("debug: false", self.loader)
        for forbidden_log_value in (
            "error.toString()",
            "error.message",
            "publishableKey}",
            "url}",
        ):
            self.assertNotIn(forbidden_log_value, self.loader)

    def test_flutter_sources_have_no_real_key_patterns(self) -> None:
        content = "\n".join((self.loader, self.config, self.main, self.env_example))
        patterns = (
            r"AIza[0-9A-Za-z_-]{35}",
            r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+",
            r"sb_(?:publishable|secret)_[A-Za-z0-9_-]{20,}",
        )
        for pattern in patterns:
            self.assertIsNone(re.search(pattern, content))


if __name__ == "__main__":
    unittest.main()
