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


if __name__ == "__main__":
    unittest.main(verbosity=2)
