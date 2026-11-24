"""
Linux app: a quota cache written by an older version must not keep the old "New release available" banner.
Run:  python3 tests/linux_update_cache.test.py

Regression of the macOS bug: right after an update the first window showed the notice for the version just installed,
because the cache (fresh for 30s) still said "update available". Same pattern lived in linux/quota-hub.py.
"""
import importlib.util
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("quota_hub", ROOT / "linux" / "quota-hub.py")
qh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qh)  # does not start the GUI (main() only runs under __main__)

TMP = Path(tempfile.mkdtemp(prefix="aigauge-linux-"))
(TMP / "core").mkdir()
UPDATER = TMP / "core" / "updater.js"
qh.ENGINE_SCRIPT = TMP / "core" / "engine.js"
qh.CACHE_FILE = TMP / "quota_cache.json"


def set_running(version):
    UPDATER.write_text(f"const CURRENT_VERSION = '{version}';\n", encoding="utf-8")


def quota(cur, latest, avail, age=5, version=None):
    return {
        "account": "x", "groups": [], "timestamp": time.time() - age, "version": version or cur,
        "update": {"current_version": cur, "latest_version": latest, "update_available": avail,
                   "download_url": "https://example.test/dl"},
    }


class LinuxUpdateCache(unittest.TestCase):
    def test_running_version_comes_from_the_bundled_engine(self):
        set_running("1.2.1")
        self.assertEqual(qh.running_version(), "1.2.1")

    def test_stale_banner_is_cleared_after_the_update(self):
        set_running("1.2.1")
        q = qh.reconcile_update(quota("1.2.0", "1.2.1", True))   # cache written by 1.2.0 says "1.2.1 available"
        self.assertFalse(q["update"]["update_available"])
        self.assertEqual(q["update"]["current_version"], "1.2.1")
        self.assertEqual(q["version"], "1.2.1")

    def test_a_real_update_is_still_shown(self):
        set_running("1.2.0")
        self.assertTrue(qh.reconcile_update(quota("1.2.0", "1.2.1", True))["update"]["update_available"])

    def test_newer_app_than_announced_has_no_banner(self):
        set_running("1.3.0")
        self.assertFalse(qh.reconcile_update(quota("1.2.0", "1.2.1", True))["update"]["update_available"])

    def test_unreadable_running_version_changes_nothing(self):
        UPDATER.write_text("// no version here", encoding="utf-8")
        self.assertTrue(qh.reconcile_update(quota("1.2.0", "1.2.1", True))["update"]["update_available"])

    def test_title_version_is_the_running_one_not_the_cached_one(self):
        set_running("1.2.1")
        self.assertEqual(qh.get_app_version(quota("1.2.0", "1.2.1", True)), "1.2.1")

    def test_cache_from_another_version_is_not_fresh(self):
        set_running("1.2.1")
        self.assertFalse(qh.cache_is_from_this_version(quota("1.2.0", "1.2.1", True)))
        self.assertTrue(qh.cache_is_from_this_version(quota("1.2.1", "1.2.1", False)))

    def test_load_quota_does_not_use_the_30s_shortcut_for_an_old_version_cache(self):
        set_running("1.2.1")
        qh.CACHE_FILE.write_text(json.dumps(quota("1.2.0", "1.2.1", True, age=5)), encoding="utf-8")
        with mock.patch.object(qh.subprocess, "run", side_effect=OSError("engine unavailable")) as run:
            got = qh.load_quota()
        self.assertTrue(run.called, "the engine must run again after an update")
        self.assertFalse(got["update"]["update_available"], "and the engine-less fallback is reconciled too")

    def test_load_quota_still_uses_the_shortcut_for_a_same_version_cache(self):
        set_running("1.2.1")
        qh.CACHE_FILE.write_text(json.dumps(quota("1.2.1", "1.2.1", False, age=5)), encoding="utf-8")
        with mock.patch.object(qh.subprocess, "run", side_effect=AssertionError("must not run")):
            got = qh.load_quota()
        self.assertTrue(got["from_cache"])

    def test_version_compare(self):
        n = qh.version_is_newer
        self.assertTrue(n("1.2.1", "1.2.0")); self.assertTrue(n("1.10.0", "1.9.9")); self.assertTrue(n("v1.3", "1.2.9"))
        self.assertFalse(n("1.2.1", "1.2.1")); self.assertFalse(n("1.2", "1.2.0")); self.assertFalse(n("1.2.0", "1.2.1"))

    def test_parse_sha256sums(self):
        h = "a" * 64
        txt = f"{h}  AI-Gauge-Linux-vh2c.zip\n{'b'*64} *other.zip\n"
        self.assertEqual(qh.parse_sha256sums(txt, "AI-Gauge-Linux-vh2c.zip"), h)
        self.assertEqual(qh.parse_sha256sums(txt, "other.zip"), "b" * 64)
        self.assertIsNone(qh.parse_sha256sums(txt, "missing.zip"))

    def test_perform_linux_in_place_update_and_checksum_guard(self):
        import hashlib, io, zipfile
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            install_dir = td_path / "installed"
            (install_dir / "core").mkdir(parents=True)
            (install_dir / "core" / "updater.js").write_text("old", encoding="utf-8")
            (install_dir / "quota-hub.py").write_text("old-py", encoding="utf-8")

            buf = io.BytesIO()
            with zipfile.ZipFile(buf, "w") as zf:
                zf.writestr("core/updater.js", "new-core")
                zf.writestr("linux/quota-hub.py", "new-py")
            zip_bytes = buf.getvalue()
            good_hash = hashlib.sha256(zip_bytes).hexdigest()

            def fake_urlopen(req, timeout=30):
                url = req.full_url if hasattr(req, "full_url") else str(req)
                if url.endswith("SHA256SUMS.txt"):
                    return io.BytesIO(f"{good_hash}  AI-Gauge-Linux-vh2c.zip\n".encode("utf-8"))
                return io.BytesIO(zip_bytes)

            with mock.patch.object(qh.urllib.request, "urlopen", side_effect=fake_urlopen):
                ok, err = qh.perform_linux_in_place_update(install_dir, "1.3.2", base_url="https://example.test")
            self.assertTrue(ok, err)
            self.assertEqual((install_dir / "core" / "updater.js").read_text(encoding="utf-8"), "new-core")
            self.assertEqual((install_dir / "quota-hub.py").read_text(encoding="utf-8"), "new-py")

            def bad_urlopen(req, timeout=30):
                url = req.full_url if hasattr(req, "full_url") else str(req)
                if url.endswith("SHA256SUMS.txt"):
                    return io.BytesIO(f"{'0'*64}  AI-Gauge-Linux-vh2c.zip\n".encode("utf-8"))
                return io.BytesIO(zip_bytes)

            (install_dir / "quota-hub.py").write_text("keep-me", encoding="utf-8")
            with mock.patch.object(qh.urllib.request, "urlopen", side_effect=bad_urlopen):
                ok2, err2 = qh.perform_linux_in_place_update(install_dir, "1.3.2", base_url="https://example.test")
            self.assertFalse(ok2)
            self.assertIn("Checksum mismatch", err2)
            self.assertEqual((install_dir / "quota-hub.py").read_text(encoding="utf-8"), "keep-me")

    def test_hud_auto_orientation_edges_and_center(self):
        fn = qh.infer_hud_orientation_for_rect
        # Near bottom center -> horizontal
        self.assertEqual(fn(850, 920, 118, 220, 1920, 1080, "vertical"), "horizontal")
        # Near top center -> horizontal
        self.assertEqual(fn(850, 10, 118, 220, 1920, 1080, "vertical"), "horizontal")
        # Near left edge -> vertical
        self.assertEqual(fn(10, 450, 500, 134, 1920, 1080, "horizontal"), "vertical")
        # Near right edge -> vertical
        self.assertEqual(fn(1400, 450, 500, 134, 1920, 1080, "horizontal"), "vertical")
        # Middle of screen -> keeps current orientation
        self.assertEqual(fn(700, 400, 118, 220, 1920, 1080, "vertical"), "vertical")
        self.assertEqual(fn(700, 400, 500, 134, 1920, 1080, "horizontal"), "horizontal")


if __name__ == "__main__":
    unittest.main(verbosity=2)
