import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PUBSPEC = REPO_ROOT / "pubspec.yaml"
ANDROID_MANIFEST = REPO_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
DIRECTIONS_URI = (
    REPO_ROOT
    / "lib"
    / "features"
    / "stores"
    / "domain"
    / "google_maps_directions.dart"
)
EXTERNAL_LAUNCHER = (
    REPO_ROOT
    / "lib"
    / "features"
    / "stores"
    / "data"
    / "external_uri_launcher.dart"
)


class ExternalDirectionsSecurityTest(unittest.TestCase):
    def test_uses_only_the_approved_url_launcher_dependency(self) -> None:
        pubspec = PUBSPEC.read_text(encoding="utf-8")

        self.assertIn("url_launcher: 6.3.2", pubspec)
        self.assertNotIn("google_directions", pubspec)
        self.assertNotIn("google_routes", pubspec)

    def test_directions_uri_uses_maps_urls_without_api_calls(self) -> None:
        source = DIRECTIONS_URI.read_text(encoding="utf-8")

        self.assertIn("www.google.com", source)
        self.assertIn("/maps/dir/", source)
        self.assertNotIn("directions.googleapis.com", source)
        self.assertNotIn("routes.googleapis.com", source)
        self.assertNotIn("package:http", source)
        self.assertNotIn("apiKey", source)

    def test_launcher_does_not_preflight_or_open_an_in_app_webview(self) -> None:
        source = EXTERNAL_LAUNCHER.read_text(encoding="utf-8")

        self.assertIn("launchUrl", source)
        self.assertIn("LaunchMode.externalNonBrowserApplication", source)
        self.assertIn("LaunchMode.externalApplication", source)
        self.assertNotIn("canLaunchUrl", source)
        self.assertNotIn("inAppWebView", source)

    def test_no_location_permissions_were_added(self) -> None:
        manifest = ANDROID_MANIFEST.read_text(encoding="utf-8")

        for permission in (
            "ACCESS_FINE_LOCATION",
            "ACCESS_COARSE_LOCATION",
            "ACCESS_BACKGROUND_LOCATION",
        ):
            self.assertNotIn(permission, manifest)


if __name__ == "__main__":
    unittest.main()
