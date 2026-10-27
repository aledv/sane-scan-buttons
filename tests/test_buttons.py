"""Unit tests for the button logic (no scanner needed). Run: python -m unittest discover -s tests -v"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))

import buttons  # noqa: E402


class ButtonsTest(unittest.TestCase):
    def test_press_is_reported_once(self):
        up = {"scan": 0, "copy": 0}
        down = {"scan": 1, "copy": 0}
        self.assertEqual(buttons.newly_pressed(up, down), ["scan"])
        self.assertEqual(buttons.newly_pressed(down, down), [])  # still held: no repeat
        self.assertEqual(buttons.newly_pressed(down, up), [])  # released

    def test_pick_device(self):
        devices = [("net:host:x", "", "", ""), ("genesys:libusb:001:004", "Canon", "LiDE 100", "flatbed")]
        self.assertEqual(buttons.pick_device(devices, "genesys:"), "genesys:libusb:001:004")
        self.assertEqual(buttons.pick_device(devices), "net:host:x")
        self.assertIsNone(buttons.pick_device(devices, "epson2:"))
        self.assertIsNone(buttons.pick_device([]))


if __name__ == "__main__":
    unittest.main()
