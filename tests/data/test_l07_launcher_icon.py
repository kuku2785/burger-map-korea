"""Structural checks for the XML-only Android launcher icon resources."""

from __future__ import annotations

from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android" / "app" / "src" / "main" / "res"
ANDROID = "{http://schemas.android.com/apk/res/android}"


class LauncherIconResourcesTest(unittest.TestCase):
    def test_adaptive_icon_has_background_and_safe_foreground(self) -> None:
        resource = RES / "mipmap-anydpi-v26" / "ic_launcher.xml"
        root = ET.parse(resource).getroot()
        self.assertEqual(root.tag, "adaptive-icon")
        layers = {child.tag: child.attrib[f"{ANDROID}drawable"] for child in root}
        self.assertEqual(layers["background"], "@color/launcher_icon_background")
        self.assertEqual(layers["foreground"], "@drawable/ic_launcher_foreground")

        foreground = ET.parse(RES / "drawable" / "ic_launcher_foreground.xml").getroot()
        self.assertEqual(foreground.attrib[f"{ANDROID}viewportWidth"], "108")
        self.assertEqual(foreground.attrib[f"{ANDROID}viewportHeight"], "108")

    def test_android_13_variant_provides_monochrome_icon(self) -> None:
        root = ET.parse(RES / "mipmap-anydpi-v33" / "ic_launcher.xml").getroot()
        layers = {child.tag: child.attrib[f"{ANDROID}drawable"] for child in root}
        self.assertEqual(layers["monochrome"], "@drawable/ic_launcher_monochrome")

    def test_legacy_vector_and_svg_preview_share_the_icon_paths(self) -> None:
        legacy = (RES / "mipmap-anydpi-v21" / "ic_launcher.xml").read_text(encoding="utf-8")
        preview = (ROOT / "docs" / "assets" / "burger-map-launcher-preview.svg").read_text(
            encoding="utf-8"
        )
        self.assertIn("M54,22C38.5,22", legacy)
        self.assertIn("M54,22C38.5,22", preview)
        self.assertIn("M41.7,47.6C41.7,42.7", legacy)
        self.assertIn("M41.7,47.6C41.7,42.7", preview)
        self.assertIn("#2F6B4F", preview)
        self.assertIn("#F8F7F3", preview)


if __name__ == "__main__":
    unittest.main()
