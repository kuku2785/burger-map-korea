import re
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ANDROID_APP = REPO_ROOT / "android" / "app"
BUILD_GRADLE = ANDROID_APP / "build.gradle.kts"
MANIFEST = ANDROID_APP / "src" / "main" / "AndroidManifest.xml"
MAIN_ACTIVITY = (
    ANDROID_APP
    / "src"
    / "main"
    / "kotlin"
    / "com"
    / "burgermapkorea"
    / "app"
    / "MainActivity.kt"
)
OLD_MAIN_ACTIVITY = (
    ANDROID_APP
    / "src"
    / "main"
    / "kotlin"
    / "com"
    / "burgermap"
    / "burger_map_korea"
    / "MainActivity.kt"
)


class AndroidReleaseConfigurationTest(unittest.TestCase):
    def test_application_id_namespace_and_main_activity_match(self) -> None:
        gradle = BUILD_GRADLE.read_text(encoding="utf-8")
        activity = MAIN_ACTIVITY.read_text(encoding="utf-8")

        self.assertIn('namespace = "com.burgermapkorea.app"', gradle)
        self.assertIn('applicationId = "com.burgermapkorea.app"', gradle)
        self.assertIn("package com.burgermapkorea.app", activity)
        self.assertTrue(MAIN_ACTIVITY.is_file())
        self.assertFalse(OLD_MAIN_ACTIVITY.exists())

    def test_old_application_id_is_absent_from_production_android_source(self) -> None:
        production_files = [BUILD_GRADLE]
        production_files.extend(
            path
            for path in (ANDROID_APP / "src" / "main").rglob("*")
            if path.is_file()
        )
        production_text = "\n".join(
            path.read_text(encoding="utf-8", errors="ignore")
            for path in production_files
        )

        self.assertNotIn("com.burgermap.burger_map_korea", production_text)

    def test_android_label_uses_approved_korean_name(self) -> None:
        manifest = MANIFEST.read_text(encoding="utf-8")
        self.assertIn('android:label="버거맵 코리아"', manifest)

    def test_release_does_not_fall_back_to_debug_signing(self) -> None:
        gradle = BUILD_GRADLE.read_text(encoding="utf-8")
        self.assertNotRegex(
            gradle,
            re.compile(r"signingConfig\s*=.*getByName\(\s*\"debug\"\s*\)"),
        )
        self.assertNotIn("ALLOW_INSECURE_RELEASE", gradle)
        self.assertIn('signingConfigs.getByName("release")', gradle)

    def test_release_signing_requires_all_properties(self) -> None:
        gradle = BUILD_GRADLE.read_text(encoding="utf-8")
        for property_name in (
            "storeFile",
            "storePassword",
            "keyAlias",
            "keyPassword",
        ):
            self.assertIn(f'"{property_name}"', gradle)

        self.assertIn("invalidProperties.isNotEmpty()", gradle)
        self.assertIn('contains("REPLACE", ignoreCase = true)', gradle)

    def test_release_signing_checks_configuration_and_keystore_files(self) -> None:
        gradle = BUILD_GRADLE.read_text(encoding="utf-8")
        self.assertIn('rootProject.file("key.properties")', gradle)
        self.assertIn("if (!keyPropertiesFile.isFile)", gradle)
        self.assertIn("if (!resolvedKeystoreFile.isFile)", gradle)
        self.assertIn("if (releaseBuildRequested)", gradle)

    def test_key_properties_template_contains_only_expected_keys(self) -> None:
        template = REPO_ROOT / "android" / "key.properties.example"
        values = {}
        for line in template.read_text(encoding="utf-8").splitlines():
            key, value = line.split("=", maxsplit=1)
            values[key] = value

        self.assertEqual(
            set(values),
            {"storeFile", "storePassword", "keyAlias", "keyPassword"},
        )
        self.assertEqual(values["storeFile"], "upload-keystore.jks")
        self.assertEqual(values["storePassword"], "REPLACE_LOCALLY")
        self.assertEqual(values["keyPassword"], "REPLACE_LOCALLY")

    def test_real_signing_files_are_not_tracked_and_are_ignored(self) -> None:
        gitignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("/android/key.properties", gitignore)
        self.assertIn("*.jks", gitignore)
        self.assertIn("*.keystore", gitignore)
        self.assertIn("!/android/key.properties.example", gitignore)

        tracked = subprocess.run(
            [
                "git",
                "ls-files",
                "--",
                "android/key.properties",
                "android/app/upload-keystore.jks",
            ],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(tracked.stdout.strip(), "")

    def test_release_bundle_verifier_remains_available(self) -> None:
        verifier = REPO_ROOT / "scripts" / "release" / "verify_release_bundle.py"
        self.assertTrue(verifier.is_file())


if __name__ == "__main__":
    unittest.main()
