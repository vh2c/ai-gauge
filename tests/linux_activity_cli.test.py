"""
Tests for Linux CLI activity indicators, adaptive polling labels, and activity UI helpers.
Run: python3 tests/linux_activity_cli.test.py
"""
import contextlib
import importlib.util
import io
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("quota_hub", ROOT / "linux" / "quota-hub.py")
qh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qh)


class LinuxActivityCliTests(unittest.TestCase):
    def test_print_cli_shows_working_waiting_idle_and_polling_cadence(self):
        quota = {
            "account": "dev@vh2c.test",
            "plan": "Pro",
            "updated_at": "10:00:00",
            "from_cache": False,
            "recommended_poll_seconds": 30,
            "activity": {
                "overall_status": "waiting",
                "recommended_poll_seconds": 30,
                "providers": {
                    "antigravity": {
                        "status": "waiting",
                        "detail": "ai_gauge · Waiting for your response",
                    },
                    "claude_pro": {
                        "status": "working",
                        "detail": "ai_gauge · Running Bash",
                    },
                    "chatgpt_subscription": {
                        "status": "idle",
                        "detail": "",
                    },
                },
            },
            "groups": [
                {
                    "name": "Gemini Models",
                    "provider": "Antigravity (Live)",
                    "buckets": [{"id": "ag1", "name": "5h", "remaining_pct": 95, "reset_in": "4h"}],
                },
                {
                    "name": "Claude",
                    "provider": "Claude Pro",
                    "buckets": [{"id": "cl1", "name": "5h", "remaining_pct": 80, "reset_in": "3h"}],
                },
                {
                    "name": "ChatGPT",
                    "provider": "ChatGPT",
                    "buckets": [{"id": "cg1", "name": "3h", "remaining_pct": 100, "reset_in": "2h"}],
                },
            ],
        }
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            qh.print_cli(quota)
        out = buf.getvalue()
        self.assertIn("Polling 30s (active)", out)
        self.assertIn("[WAITING · ai_gauge · Waiting for your response]", out)
        self.assertIn("[WORKING · ai_gauge · Running Bash]", out)
        self.assertIn("[IDLE]", out)

    def test_print_cli_idle_polling_label(self):
        quota = {
            "account": "dev@vh2c.test",
            "plan": "Pro",
            "updated_at": "10:05:00",
            "from_cache": False,
            "recommended_poll_seconds": 300,
            "activity": {
                "overall_status": "idle",
                "recommended_poll_seconds": 300,
                "providers": {
                    "claude_pro": {"status": "idle", "detail": ""},
                },
            },
            "groups": [
                {
                    "name": "Claude",
                    "provider": "Claude Pro",
                    "buckets": [{"id": "cl1", "name": "5h", "remaining_pct": 100, "reset_in": "5h"}],
                }
            ],
        }
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            qh.print_cli(quota)
        out = buf.getvalue()
        self.assertIn("Polling 5 min (idle)", out)
        self.assertIn("[IDLE]", out)

    def test_activity_helpers_and_hud_sections(self):
        self.assertEqual(qh.blend_hex("#8FBCFF", "#181818", 0.0), "#181818")
        self.assertEqual(qh.blend_hex("#8FBCFF", "#181818", 1.0), "#8FBCFF")
        tip = qh.format_activity_tooltip(
            "Claude",
            {"status": "working", "detail": "ai_gauge · Running Edit", "age_seconds": 4},
            30,
        )
        self.assertIn("Claude · Working", tip)
        self.assertIn("ai_gauge · Running Edit", tip)
        self.assertIn("Updated 4s ago", tip)
        self.assertIn("30s (active)", tip)

        fp1 = qh.activity_fingerprint({"overall_status": "working", "recommended_poll_seconds": 30, "providers": {"claude_pro": {"status": "working", "detail": "a"}}})
        fp2 = qh.activity_fingerprint({"overall_status": "idle", "recommended_poll_seconds": 300, "providers": {"claude_pro": {"status": "idle", "detail": ""}}})
        self.assertNotEqual(fp1, fp2)

    def test_demo_cli_subprocess_exits_zero_and_shows_activity(self):
        proc = subprocess.run(
            [sys.executable, str(ROOT / "linux" / "quota-hub.py"), "--demo", "--cli"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("[WAITING", proc.stdout)
        self.assertIn("[WORKING", proc.stdout)
        self.assertIn("[IDLE]", proc.stdout)
        self.assertIn("Polling 30s (active)", proc.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
