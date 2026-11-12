"""Regression checks for the final flash-sale recheck."""
import sys
import json
import tempfile
import unittest
from types import SimpleNamespace
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scraper"))
import scan_tgdd
import scan_market


class FlashVerifyTests(unittest.TestCase):
    def test_windows_variant_snapshot_requires_same_batch_and_fresh_time(self):
        now = datetime.now(timezone.utc)
        snapshot = {"batch_id": "batch-this-run", "scanned_at": now.isoformat(),
                    "rows": [{"slug": "oppo-a7-pro-5g-6gb-256gb", "rrp": 14490000, "red": 13990000}]}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "tgdd_variant_live.json"
            path.write_text(json.dumps(snapshot), encoding="utf-8")
            old_cache = scan_tgdd._LOCAL_VARIANT_ROWS
            try:
                with (patch.object(scan_tgdd, "LOCAL_VARIANTS", path),
                      patch.dict("os.environ", {"TGDD_BATCH_ID": "batch-this-run"})):
                    scan_tgdd._LOCAL_VARIANT_ROWS = None
                    self.assertEqual(scan_tgdd.current_local_variants()["oppo-a7-pro-5g-6gb-256gb"],
                                     (14490000, 13990000))
                    snapshot["batch_id"] = "previous-run"
                    path.write_text(json.dumps(snapshot), encoding="utf-8")
                    scan_tgdd._LOCAL_VARIANT_ROWS = None
                    self.assertEqual(scan_tgdd.current_local_variants(), {})
                    snapshot["batch_id"] = "batch-this-run"
                    snapshot["scanned_at"] = (now - timedelta(minutes=46)).isoformat()
                    path.write_text(json.dumps(snapshot), encoding="utf-8")
                    scan_tgdd._LOCAL_VARIANT_ROWS = None
                    self.assertEqual(scan_tgdd.current_local_variants(), {})
            finally:
                scan_tgdd._LOCAL_VARIANT_ROWS = old_cache

    def test_final_flat_a7_uses_exact_live_windows_batch(self):
        first = {"model": "A7 Pro 5G 6GB/256GB",
                 "url": "https://www.thegioididong.com/dtdd/oppo-a7-pro-5g-6gb-256gb",
                 "status": "active", "rrp": 13490000, "red": 13490000, "pmh": 0,
                 "banner": False, "kind": "moi", "flash_src": []}
        with (patch.object(scan_tgdd, "fetch_live_flashsale_slugs", return_value=set()),
              patch.object(scan_tgdd, "scan_one", return_value=first.copy()),
              patch.object(scan_tgdd, "last_check_tu_danh_muc", return_value=None),
              patch.object(scan_tgdd, "current_local_variants", return_value={
                  "oppo-a7-pro-5g-6gb-256gb": (14490000, 13990000)}),
              patch.object(scan_tgdd, "apply_variant_guard", side_effect=lambda model, row, base: row)):
            result = scan_tgdd.verify_flash_rows([first])[0]
        self.assertEqual((result["status"], result["rrp"], result["red"], result["pmh"]),
                         ("active", 14490000, 13990000, 500000))

    def test_final_rechecks_exact_a7_api_after_pdp_loses_red(self):
        first = {"model": "A7 Pro 5G 6GB/256GB",
                 "url": "https://www.thegioididong.com/dtdd/oppo-a7-pro-5g-6gb-256gb",
                 "status": "active", "rrp": 14490000, "red": 13990000, "pmh": 500000,
                 "banner": False, "kind": "brand_tab", "flash_src": []}
        sibling_pdp = scan_tgdd.build_result(13490000, 13490000, False, 0, "moi")
        exact = scan_tgdd.build_result(14490000, 13990000, False, 0, "brand_tab")
        with (patch.object(scan_tgdd, "fetch_live_flashsale_slugs", return_value=set()),
              patch.object(scan_tgdd, "scan_one", return_value=sibling_pdp),
              patch.object(scan_tgdd, "last_check_tu_danh_muc", return_value=exact) as popup,
              patch.object(scan_tgdd, "current_local_variants", return_value={}),
              patch.object(scan_tgdd, "apply_variant_guard", side_effect=lambda model, row, base: row)):
            result = scan_tgdd.verify_flash_rows([first])[0]
        popup.assert_called_once_with(first)
        self.assertEqual((result["status"], result["rrp"], result["red"], result["pmh"]),
                         ("active", 14490000, 13990000, 500000))

    def test_selected_variant_card_rejects_main_sku_price(self):
        target = "oppo-a7-pro-5g-6gb-256gb"
        main = "oppo-a7-pro-5g-8gb-128gb"
        card = (f'<div data-product-code="1"><a title="OPPO A7 Pro" href="/dtdd/{main}">A7</a>'
                f'<a data-disable-progress="true" href="/dtdd/{target}">6GB/256GB</a>'
                f'<a class="font-700 text-red-7" href="/dtdd/{main}"><span>11.870.000đ</span></a>'
                f'<a href="/dtdd/{main}"><del>13.490.000đ</del></a></div>')
        self.assertIsNone(scan_tgdd.parse_selected_variant_card(card, target))
        switched = (card.replace(f'href="/dtdd/{main}"', f'href="/dtdd/{target}"')
                    .replace('11.870.000đ', '13.990.000đ')
                    .replace('13.490.000đ', '14.490.000đ'))
        result = scan_tgdd.parse_selected_variant_card(switched, target)
        self.assertEqual((result["status"], result["red"], result["rrp"]),
                         ("active", 13990000, 14490000))

    def test_fpt_batch_requires_matching_id_freshness_and_valid_prices(self):
        now = datetime.now(timezone.utc)
        rows = [{"r": "FPT Shop", "b": ["Apple", "Samsung", "OPPO", "Xiaomi"][i % 4],
                 "n": f"Model {i}", "u": f"https://fptshop.com.vn/dien-thoai/model-{i}?sku={i}",
                 "p": 5000000, "o": 6000000, "k": "Khuyến mãi"} for i in range(80)]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "fpt_live.json"
            snapshot = {"batch_id": "this-run", "scanned_at": now.isoformat(), "rows": rows}
            path.write_text(json.dumps(snapshot), encoding="utf-8")
            self.assertEqual(len(scan_market.fpt_rows_via_local_batch(path, "this-run", now)), 80)
            self.assertEqual(scan_market.fpt_rows_via_local_batch(path, "other-run", now), [])
            self.assertEqual(scan_market.fpt_rows_via_local_batch(path, "this-run", now + timedelta(hours=2)), [])
            rows[0]["p"] = 7000000
            path.write_text(json.dumps(snapshot), encoding="utf-8")
            self.assertEqual(scan_market.fpt_rows_via_local_batch(path, "this-run", now), [])

    def verify(self, first, second):
        with (patch.object(scan_tgdd, "fetch_live_flashsale_slugs", return_value=set()),
              patch.object(scan_tgdd, "scan_one", return_value=second),
              patch.object(scan_tgdd, "fetch_model_from_brand_hub", return_value=None),
              patch.object(scan_tgdd, "last_check_tu_danh_muc", return_value=None),
              patch.object(scan_tgdd, "apply_variant_guard", side_effect=lambda model, row, base: row)):
            return scan_tgdd.verify_flash_rows([first])[0]

    def test_final_no_price_rechecks_live_brand_card(self):
        first = {"model": "iPhone Duo 256GB", "url": "https://www.thegioididong.com/dtdd/iphone-duo",
                 "status": "active", "rrp": 60000000, "red": 60000000, "pmh": 0,
                 "banner": False, "kind": "brand_tab", "flash_src": []}
        live = scan_tgdd.build_result(64990000, 64990000, False, 0, "brand_tab")
        with (patch.object(scan_tgdd, "fetch_live_flashsale_slugs", return_value=set()),
              patch.object(scan_tgdd, "scan_one", return_value={"status": "no_price"}),
              patch.object(scan_tgdd, "fetch_model_from_brand_hub", return_value=live) as hub,
              patch.object(scan_tgdd, "apply_variant_guard", side_effect=lambda model, row, base: row)):
            result = scan_tgdd.verify_flash_rows([first])[0]
        hub.assert_called_once_with("iphone-duo", refresh=True)
        self.assertEqual((result["status"], result["rrp"], result["pmh"]),
                         ("active", 64990000, 0))

    def test_final_hub_refresh_does_not_use_old_catalog_cache(self):
        old_items, old_visited = scan_tgdd._CATALOG_ITEMS, scan_tgdd._HUB_VISITED
        html = ('<div data-product-code="1" data-model-code="2">'
                '<a href="/dtdd/iphone-duo">iPhone Duo 256GB</a>'
                '<a class="text-red-7"><span>64.990.000đ</span></a></div>')
        scan_tgdd._CATALOG_ITEMS = {"iphone-duo": {"rrp": 60000000, "red": 60000000}}
        scan_tgdd._HUB_VISITED = {"iphone-duo|https://www.thegioididong.com/dtdd-apple-iphone"}
        try:
            with patch.object(scan_tgdd, "http_get", return_value=SimpleNamespace(status_code=200, text=html)) as get:
                result = scan_tgdd.fetch_model_from_brand_hub("iphone-duo", refresh=True)
            self.assertGreater(get.call_count, 0)
            self.assertEqual(result["rrp"], 64990000)
        finally:
            scan_tgdd._CATALOG_ITEMS = old_items
            scan_tgdd._HUB_VISITED = old_visited

    def test_current_scan_cannot_load_pinned_prices(self):
        self.assertFalse(hasattr(scan_tgdd, "PINNED_PRICES"))
        self.assertFalse(hasattr(scan_tgdd, "apply_pinned_prices"))

    def test_popup_reads_exact_variant_and_rejects_conflicting_colors(self):
        target = "oppo-a7-pro-5g-8gb-256gb"
        data = {"data": {"boxBuys": [
            {"url": "dtdd/oppo-a7-pro-5g-6gb-256gb", "productPrices": [
                {"price": 13990000, "sysPrice": 14490000, "isCanBuy": True}]},
            {"url": f"dtdd/{target}", "productPrices": [
                {"price": 14680000, "sysPrice": 15490000, "isCanBuy": True}]},
        ]}}
        result = scan_tgdd.parse_popup_variant_prices(data, target)
        self.assertEqual((result["rrp"], result["red"], result["pmh"]),
                         (15490000, 14680000, 810000))
        data["data"]["boxBuys"].append({"url": f"dtdd/{target}", "productPrices": [
            {"price": 14990000, "sysPrice": 15490000, "isCanBuy": True}]})
        self.assertIsNone(scan_tgdd.parse_popup_variant_prices(data, target))

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
