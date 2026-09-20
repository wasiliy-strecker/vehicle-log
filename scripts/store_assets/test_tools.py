import importlib.util
from pathlib import Path
import subprocess
from unittest.mock import patch
import tempfile
import unittest
import zipfile


def module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


device = module("device")
package = module("package")


class StoreToolsTest(unittest.TestCase):
    def test_physical_device_and_implicit_target_rejected(self):
        for value in ["A5CS024205005243", "", "emulator-5580;echo", "localhost:5555"]:
            with self.assertRaises(ValueError):
                device.validate_serial(value)
        self.assertEqual(device.validate_serial("emulator-5580"), "emulator-5580")

    def test_foreign_emulator_rejected(self):
        for replies in [[b"0"], [b"1", b"pixel_tablet_api35\nOK"]]:
            with patch.object(device.Device, "run", side_effect=replies):
                with self.assertRaises(ValueError):
                    device.Device("emulator-5580")

    def test_png_format_and_truncation_rejected(self):
        with tempfile.TemporaryDirectory(prefix="fz-png-test-") as folder:
            path = Path(folder) / "image.png"
            for encoding, is_icon in [("PNG24", False), ("PNG32", True)]:
                subprocess.run(["convert", "-size", "8x8", "xc:white",
                                f"{encoding}:{path}"], check=True)
                self.assertEqual(package.png_info(path, icon=is_icon)[:2], (8, 8))
                with self.assertRaises(ValueError):
                    package.png_info(path, icon=not is_icon)
            path.write_bytes(path.read_bytes()[:33])
            with self.assertRaises(subprocess.CalledProcessError):
                package.png_info(path, icon=True)
            subprocess.run(["convert", "-size", "8x8", "xc:none",
                            f"PNG32:{path}"], check=True)
            with self.assertRaises(ValueError):
                package.png_info(path, icon=True)

    def test_missing_assets_rejected(self):
        with tempfile.TemporaryDirectory(prefix="fz-package-test-") as folder:
            with self.assertRaises(ValueError):
                package.validate(Path(folder))

    def test_changed_or_missing_release_payload_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            aab, apk = Path(folder) / "source.aab", Path(folder) / "capture.apk"
            with zipfile.ZipFile(aab, "w") as archive:
                archive.writestr("base/lib/x86_64/libapp.so", b"release")
                archive.writestr("base/assets/example", b"asset")
            for content in [b"release", b"different"]:
                with zipfile.ZipFile(apk, "w") as archive:
                    archive.writestr("lib/x86_64/libapp.so", content)
                    archive.writestr("assets/example", b"asset")
                if content == b"release":
                    package.verify_payloads(aab, apk)
                else:
                    with self.assertRaises(ValueError):
                        package.verify_payloads(aab, apk)
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("lib/x86_64/libapp.so", b"release")
            with self.assertRaises(ValueError):
                package.verify_payloads(aab, apk)

    def test_alt_text_limits(self):
        self.assertTrue(all(0 < len(text) <= 140 for text in package.PHONE_ALT + package.TABLET_ALT))


if __name__ == "__main__":
    unittest.main()
