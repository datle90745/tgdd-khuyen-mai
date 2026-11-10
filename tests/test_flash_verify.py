"""Regression checks for the final flash-sale recheck."""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scraper"))
import scan_tgdd


class FlashVerifyTests(unittest.TestCase):
    def verify(self, first, second):
        with (patch.object(scan_tgdd, "fetch_live_flashsale_slugs", return_value=set()),
              patch.object(scan_tgdd, "scan_one", return_value=second),
              patch.object(scan_tgdd, "apply_variant_guard", side_effect=lambda model, row, base: row)):
            return scan_tgdd.verify_flash_rows([first])[0]

    def test_missing_red_on_second_pass_keeps_real_first_pass_discount(self):
        first = {"model": "Sample 8GB/256GB", "url": "https://www.thegioididong.com/dtdd/sample",
                 "status": "active", "rrp": 10990000, "red": 9770000, "pmh": 1220000,
                 "banner": False, "kind": "moi", "flash_src": []}
        second = {"status": "active", "rrp": 9770000, "red": 9770000, "pmh": 0,
                  "banner": False, "kind": "moi", "flash_src": []}
        result = self.verify(first, second)
        self.assertEqual((result["rrp"], result["red"], result["pmh"]),
                         (10990000, 9770000, 1220000))
        self.assertEqual(result["flash_src"], [])

    def test_new_flash_evidence_still_updates_row(self):
        first = {"model": "Sample 8GB/256GB", "url": "https://www.thegioididong.com/dtdd/sample",
                 "status": "active", "rrp": 10990000, "red": 9770000, "pmh": 1220000,
                 "banner": False, "kind": "moi", "flash_src": []}
        second = {"status": "active", "rrp": 10990000, "red": 9770000, "pmh": 0,
                  "banner": True, "kind": "moi-banner", "flash_src": ["quota"]}
        result = self.verify(first, second)
        self.assertEqual(result["pmh"], 0)
        self.assertTrue(result["banner"])
        self.assertEqual(result["flash_src"], ["quota"])


if __name__ == "__main__":
    unittest.main()
