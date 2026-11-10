"""Regression checks for the final flash-sale recheck."""
import sys
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scraper"))
import scan_tgdd
import scan_market


class FlashVerifyTests(unittest.TestCase):
    def verify(self, first, second):
        with (patch.object(scan_tgdd, "fetch_live_flashsale_slugs", return_value=set()),
              patch.object(scan_tgdd, "scan_one", return_value=second),
              patch.object(scan_tgdd, "apply_variant_guard", side_effect=lambda model, row, base: row)):
            return scan_tgdd.verify_flash_rows([first])[0]

    def test_missing_red_on_second_pass_does_not_reuse_first_pass_discount(self):
        first = {"model": "Sample 8GB/256GB", "url": "https://www.thegioididong.com/dtdd/sample",
                 "status": "active", "rrp": 10990000, "red": 9770000, "pmh": 1220000,
                 "banner": False, "kind": "moi", "flash_src": []}
        second = {"status": "active", "rrp": 9770000, "red": 9770000, "pmh": 0,
                  "banner": False, "kind": "moi", "flash_src": []}
        result = self.verify(first, second)
        self.assertEqual(result["status"], "error")
        self.assertIsNone(result["rrp"])
        self.assertIsNone(result["red"])
        self.assertIsNone(result["pmh"])
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

    def test_failed_final_check_does_not_reuse_first_pass_price(self):
        first = {"model": "Sample 8GB/256GB", "url": "https://www.thegioididong.com/dtdd/sample",
                 "status": "active", "rrp": 10990000, "red": 9770000, "pmh": 1220000,
                 "banner": True, "kind": "moi-banner", "flash_src": ["quota"]}
        result = self.verify(first, {"status": "no_price"})
        self.assertEqual(result["status"], "error")
        self.assertIsNone(result["pmh"])
        self.assertIsNone(result["rrp"])
        self.assertFalse(result["banner"])
        self.assertEqual(result["flash_src"], [])

    def test_failed_hub_refresh_does_not_return_previous_snapshot(self):
        old = scan_tgdd._LIVE_FLASH_SLUGS
        scan_tgdd._LIVE_FLASH_SLUGS = {"stale-product"}
        try:
            with (patch.object(scan_tgdd, "http_get", side_effect=RuntimeError("hub offline")) as get,
                  patch.object(scan_tgdd.time, "sleep")):
                with self.assertRaisesRegex(RuntimeError, "Không xác minh được hub"):
                    scan_tgdd.fetch_live_flashsale_slugs()
                self.assertEqual(get.call_count, 3)
        finally:
            scan_tgdd._LIVE_FLASH_SLUGS = old

    def test_fpt_failure_does_not_use_file_from_earlier_scan(self):
        with (patch.object(scan_market, "fpt_rows_via_erp_api", return_value=[]),
              patch.object(scan_market, "fpt_rows_via_http", return_value=[]),
              patch.object(scan_market, "fpt_rows_via_browser", return_value=[])):
            with self.assertRaisesRegex(RuntimeError, "không dùng dữ liệu cũ"):
                scan_market.scan_fpt()

    def test_fpt_erp_rows_require_recent_scraped_at(self):
        now = datetime(2026, 11, 10, 15, 0, tzinfo=ZoneInfo("Asia/Ho_Chi_Minh"))
        base = {"category": "Điện thoại", "name": "OPPO Sample",
                "sale_price": 9000000, "original_price": 10000000}
        deals = [
            {**base, "url": "https://example.com/fresh",
             "scraped_at": "2026-11-10 14:00:00"},
            {**base, "url": "https://example.com/old",
             "scraped_at": "2026-10-09 14:38:16"},
            {**base, "url": "https://example.com/no-date"}
        ]
        rows = scan_market._parse_erp_portal_deals(deals, now=now)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["u"], "https://example.com/fresh")

    def test_unexplained_flat_drop_is_unknown_not_old_price_or_zero(self):
        previous = [{"model": "A7 sample", "status": "active", "pmh": 500000}]
        current = [{"model": "A7 sample", "status": "active", "rrp": 14490000,
                    "red": 14490000, "pmh": 0, "online": 0, "choice": 0,
                    "banner": False, "kind": "moi", "rule": "den_tru_do"}]
        row = scan_tgdd.blank_flat_regressions(current, previous)[0]
        self.assertEqual(row["status"], "error")
        self.assertIsNone(row["rrp"])
        self.assertIsNone(row["red"])
        self.assertIsNone(row["pmh"])
        self.assertEqual(row["flash_src"], [])

    def test_no_previous_discount_keeps_live_flat_price(self):
        current = [{"model": "Sample", "status": "active", "rrp": 1000000,
                    "red": 1000000, "pmh": 0}]
        row = scan_tgdd.blank_flat_regressions(
            current, [{"model": "Sample", "status": "active", "pmh": 0}])[0]
        self.assertEqual(row["status"], "active")
        self.assertEqual(row["pmh"], 0)

    def test_sibling_variant_price_is_unknown_not_derived_from_baseline(self):
        result = {"status": "active", "rrp": 5590000, "red": 4990000,
                  "pmh": 600000, "banner": False, "choice": 0}
        row = scan_tgdd.apply_variant_guard(
            "A08 4GB/64GB", result, {"A08 4GB/64GB": 4790000})
        self.assertEqual(row["status"], "error")
        self.assertIsNone(row["rrp"])
        self.assertIsNone(row["red"])
        self.assertIsNone(row["pmh"])


if __name__ == "__main__":
    unittest.main()
