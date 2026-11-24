#!/usr/bin/env python3
"""
Universal AI Quota Monitor - Linux Edition
Developed by VH2C • https://vh2c.com.br

Supports:
- Full Detailed Window (Antigravity #181818 theme, cards, progress bars)
- Compact Radial HUD (Vertical dock or Horizontal bar with tachometer gauges)
- Multi-Provider Settings Window (Gemini, OpenAI, Claude, Antigravity)
- Terminal CLI Mode (--cli or headless servers)
"""

import sys
import os
import json
import time
import math
import subprocess
import glob
import webbrowser
import urllib.request
import uuid
import platform
import threading
import re
import tempfile
import shutil
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
REPO_ROOT = APP_DIR.parent
ENGINE_SCRIPT = REPO_ROOT / "core" / "engine.js"
if not ENGINE_SCRIPT.exists():
    ENGINE_SCRIPT = APP_DIR / "core" / "engine.js"
if not ENGINE_SCRIPT.exists():
    candidate = Path.home() / ".local" / "share" / "universal-ai-quota" / "core" / "engine.js"
    if candidate.exists():
        ENGINE_SCRIPT = candidate

DEMO_MODE = ("--demo" in sys.argv)
CONFIG_DIR = (Path(tempfile.gettempdir()) / "AIGaugeDemo") if DEMO_MODE else (Path.home() / ".config" / "UniversalAIQuota")
CONFIG_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_FILE = CONFIG_DIR / "config.json"
if DEMO_MODE and not CONFIG_FILE.exists():
    try:
        CONFIG_FILE.write_text('{"providers":{},"hidden_hud_gauges":[],"onboarding_completed":true}', encoding="utf-8")
    except Exception:
        pass
CACHE_FILE = CONFIG_DIR / "quota_cache.json"
PREFS_FILE = CONFIG_DIR / "prefs.json"

def get_machine_id():
    id_file = CONFIG_DIR / "device_id"
    if id_file.exists():
        try:
            val = id_file.read_text(encoding="utf-8").strip()
            if val and len(val) >= 8:
                return val
        except Exception:
            pass
    mid_file = Path("/etc/machine-id")
    if mid_file.exists():
        try:
            val = mid_file.read_text(encoding="utf-8").strip()
            if val:
                id_file.write_text(val, encoding="utf-8")
                return val
        except Exception:
            pass
    fallback = str(uuid.uuid4()).replace("-", "")
    try:
        id_file.write_text(fallback, encoding="utf-8")
    except Exception:
        pass
    return fallback

def running_version():
    """Version of the app that is running NOW: the CURRENT_VERSION of the engine bundled with it (None if unreadable)."""
    try:
        updater_path = ENGINE_SCRIPT.parent / "updater.js"
        if updater_path.exists():
            with open(updater_path, "r", encoding="utf-8") as f:
                content = f.read()
            m = re.search(r"CURRENT_VERSION\s*=\s*['\"]([^'\"]+)['\"]", content)
            if m:
                return m.group(1)
    except Exception:
        pass
    return None

def get_app_version(quota=None):
    # The running version wins: quota_cache.json may have been written by an older version of the app
    # (e.g. right after an update) and its "version" field would show the old number.
    running = running_version()
    if running:
        return running
    if quota and quota.get("version"):
        return quota.get("version")
    if quota and quota.get("update", {}).get("current_version"):
        return quota.get("update", {}).get("current_version")
    return "1.2.0"

def version_is_newer(latest, current):
    """'1.2.10' > '1.2.9'; missing parts count as 0."""
    def parts(v):
        out = []
        for piece in str(v or "").strip().lstrip("vV").split("."):
            m = re.match(r"\d+", piece)
            out.append(int(m.group(0)) if m else 0)
        return out
    a, b = parts(latest), parts(current)
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else 0
        y = b[i] if i < len(b) else 0
        if x != y:
            return x > y
    return False

def reconcile_update(quota):
    """Whether an update is available depends on the version running NOW, not on the one that wrote the cache.
    Right after updating, an old cache still says 'update available' for the version we just installed."""
    try:
        upd = quota.get("update") if isinstance(quota, dict) else None
        running = running_version()
        if not upd or not running:
            return quota
        if upd.get("update_available") and not version_is_newer(upd.get("latest_version"), running):
            upd["update_available"] = False
        if upd.get("current_version") != running:
            upd["current_version"] = running
        if quota.get("version") and quota.get("version") != running:
            quota["version"] = running
    except Exception:
        pass
    return quota

def cache_is_from_this_version(data):
    """A cache written by another version of the app is not 'fresh': the engine must run again (it detects the
    upgrade and clears the old 'new release' notice)."""
    running = running_version()
    cached = ((data.get("update") or {}).get("current_version") if isinstance(data, dict) else None)
    return (not running) or (not cached) or cached == running

_STARTUP_SENT = False  # set once the engine ran successfully after the app was opened

def load_config():
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                raw = f.read().lstrip("\ufeff")
                data = json.loads(raw)
                if "providers" not in data:
                    data["providers"] = {}
                if "hidden_hud_gauges" not in data:
                    data["hidden_hud_gauges"] = []
                return data
        except Exception:
            pass
    return {
        "providers": {
            "antigravity": {"enabled": True},
            "claude_pro": {"enabled": True},
            "chatgpt_subscription": {"enabled": True},
            "gemini": {"enabled": False, "api_key": ""},
            "openai": {"enabled": False, "api_key": ""},
            "anthropic": {"enabled": False, "api_key": ""}
        },
        "refresh_interval_seconds": 30,
        "hidden_hud_gauges": []
    }

def save_config(cfg):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
        try:
            os.chmod(CONFIG_FILE, 0o600)
            os.chmod(CONFIG_DIR, 0o700)
        except Exception:
            pass
    except Exception as e:
        print(f"Error saving settings: {e}")

def find_node():
    # 1. Check local app embedded/portable node
    local_nodes = [
        APP_DIR / "bin" / "node",
        APP_DIR.parent / "bin" / "node",
        Path.home() / ".local" / "share" / "universal-ai-quota" / "bin" / "node"
    ]
    for ln in local_nodes:
        if ln.exists() and os.access(ln, os.X_OK):
            return str(ln)

    # 2. Check standard system locations
    for p in ["/usr/bin/node", "/usr/local/bin/node", "/opt/homebrew/bin/node", "/bin/node"]:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p

    # 3. Check NVM installations
    nvm_nodes = sorted(glob.glob(os.path.expanduser("~/.nvm/versions/node/*/bin/node")), reverse=True)
    if nvm_nodes:
        return nvm_nodes[0]

    # 4. Fallback to PATH
    return "node"

def new_demo_data():
    def b(bid, name, pct, reset):
        return {"id": bid, "name": name, "remaining_pct": pct, "reset_in": reset}
    return {
        "account": "demo@aigauge.test  (MODO DEMO)",
        "plan": "DEMO",
        "updated_at": time.strftime("%H:%M:%S"),
        "version": get_app_version(),
        "tier": "free",
        "from_cache": False,
        "recommended_poll_seconds": 30,
        "activity": {
            "overall_status": "waiting",
            "active_count": 2,
            "working_count": 1,
            "waiting_count": 1,
            "recommended_poll_seconds": 30,
            "providers": {
                "antigravity": {"status": "waiting", "sessions_count": 1, "project": "ai_gauge", "summary": "Waiting for your response", "detail": "ai_gauge · Waiting for your response", "age_seconds": 14},
                "claude_pro": {"status": "working", "sessions_count": 1, "project": "ai_gauge", "summary": "Running Bash", "detail": "ai_gauge · Running Bash", "age_seconds": 3},
                "chatgpt_subscription": {"status": "idle", "sessions_count": 0, "project": "Codex", "summary": "Idle", "detail": "", "age_seconds": 940},
                "cursor": {"status": "idle", "sessions_count": 0, "project": "Cursor IDE", "summary": "Idle", "detail": "", "age_seconds": None},
            },
        },
        "announcement": {
            "type": "versao",
            "badge": "VERSION",
            "title": "Version 2.1 Available",
            "message": "Download the latest version now.",
            "action_label": "Download Update",
            "action_url": "https://github.com/vh2c/ai-gauge/releases/latest",
        },
        "promo": {
            "type": "publicidade",
            "title": "Super Offer",
            "message": "Today only: get your PRO license for just R$ 10.00",
            "action_label": None,
            "action_url": None,
            "image_url": "https://dashboard.vh2c.com.br/uploads/ads/ad_20261116_144942_2f64117f.jpg",
            "image_fit": "cover",
            "image_position": "center",
            "image_scale": 1.05,
            "duracao_segundos": None,
        },
        "groups": [
            {
                "name": "Antigravity",
                "provider": "Antigravity (Live)",
                "buckets": [
                    b("demo-ag-gemini-weekly", "Gemini Weekly Limit Remaining", 43, "4d 1h"),
                    b("demo-ag-gemini-5h", "Gemini Five Hour Limit Remaining", 98, "4h 51m"),
                    b("demo-ag-argon-weekly", "Argon Weekly Limit Remaining", 27, "4d 1h"),
                ],
            },
            {
                "name": "Claude Pro",
                "provider": "Claude Pro",
                "buckets": [
                    b("demo-claude-5h", "Claude 5 Hour Limit", 84, "4h 27m"),
                    b("demo-claude-weekly", "Claude Weekly Limit", 82, "2d 18h"),
                ],
            },
            {
                "name": "ChatGPT Plus",
                "provider": "ChatGPT",
                "buckets": [
                    b("demo-gpt4o-3h", "GPT-4o 3 Hour Limit", 100, "29d 23h"),
                    b("demo-o1-weekly", "o1 Reasoning Weekly", 100, "7d"),
                ],
            },
            {
                "name": "Cursor",
                "provider": "Cursor",
                "buckets": [
                    b("demo-cursor-fast", "Fast Requests (Claude)", 64, "14d"),
                    b("demo-cursor-month", "Monthly Billing Cycle", 12, "14d"),
                ],
            },
        ],
    }

def test_api_key_sync(provider, key):
    clean = (key or "").strip()
    if DEMO_MODE:
        return {"ok": bool(clean), "provider": provider, "status": "OK"} if clean else {"ok": False, "provider": provider, "error": "Empty key"}
    node_bin = find_node()
    env = dict(os.environ)
    extra_paths = ["/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    env["PATH"] = ":".join(extra_paths) + ":" + env.get("PATH", "")
    try:
        res = subprocess.run(
            [node_bin, str(ENGINE_SCRIPT), "--test-key", provider, clean],
            capture_output=True, text=True, env=env, timeout=12
        )
        out = (res.stdout or "").strip()
        if out:
            return json.loads(out)
    except Exception as e:
        return {"ok": False, "provider": provider, "error": str(e)}
    return {"ok": False, "provider": provider, "error": "Invalid key"}

def load_quota(force=False):
    if DEMO_MODE:
        return new_demo_data()
    if not force and CACHE_FILE.exists():
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            ts = data.get("timestamp", 0)
            if time.time() - ts < 30 and cache_is_from_this_version(data):
                data["from_cache"] = True
                data["cache_age_seconds"] = int(time.time() - ts)
                return reconcile_update(data)
        except Exception:
            pass

    node_bin = find_node()
    env = dict(os.environ)
    extra_paths = ["/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    env["PATH"] = ":".join(extra_paths) + ":" + env.get("PATH", "")

    try:
        # --startup: the app was just opened, so the engine contacts the AI Gauge API once (version/announcements).
        # Later refreshes only read the local cache (the engine re-checks after 24h).
        global _STARTUP_SENT
        cmd = [node_bin, str(ENGINE_SCRIPT)] + ([] if _STARTUP_SENT else ["--startup"])
        res = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=7)
        if res.returncode == 0 and res.stdout.strip():
            _STARTUP_SENT = True
            parsed = json.loads(res.stdout.strip())
            parsed["timestamp"] = time.time()
            parsed["from_cache"] = False
            parsed["cache_age_seconds"] = 0
            with open(CACHE_FILE, "w", encoding="utf-8") as f:
                json.dump(parsed, f, indent=2)
            return parsed
    except Exception:
        pass

    if CACHE_FILE.exists():
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return reconcile_update(json.load(f))
        except Exception:
            pass
    return None

def load_activity_only():
    if DEMO_MODE:
        return None
    node_bin = find_node()
    env = dict(os.environ)
    extra_paths = ["/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    env["PATH"] = ":".join(extra_paths) + ":" + env.get("PATH", "")
    try:
        res = subprocess.run([node_bin, str(ENGINE_SCRIPT), "--activity-only"], capture_output=True, text=True, env=env, timeout=3)
        if res.returncode == 0 and res.stdout.strip():
            return json.loads(res.stdout.strip())
    except Exception:
        pass
    return None

def blend_hex(fg_hex, bg_hex="#181818", alpha=0.42):
    try:
        fg = fg_hex.lstrip("#")
        bg = bg_hex.lstrip("#")
        fr, fg_c, fb = int(fg[0:2], 16), int(fg[2:4], 16), int(fg[4:6], 16)
        br, bg_c, bb = int(bg[0:2], 16), int(bg[2:4], 16), int(bg[4:6], 16)
        r = int(round(fr * alpha + br * (1.0 - alpha)))
        g = int(round(fg_c * alpha + bg_c * (1.0 - alpha)))
        b = int(round(fb * alpha + bb * (1.0 - alpha)))
        return f"#{r:02X}{g:02X}{b:02X}"
    except Exception:
        return fg_hex

def get_provider_activity(quota, prov_key):
    if not isinstance(quota, dict):
        return None
    act = quota.get("activity")
    if isinstance(act, dict):
        provs = act.get("providers")
        if isinstance(provs, dict) and isinstance(provs.get(prov_key), dict):
            return provs[prov_key]
    for g in quota.get("groups", []):
        if get_provider_key(g.get("name", ""), g.get("provider", "")) == prov_key:
            if isinstance(g.get("activity"), dict):
                return g["activity"]
    return None

def get_effective_poll_seconds(quota):
    if isinstance(quota, dict):
        act = quota.get("activity")
        if isinstance(act, dict) and act.get("recommended_poll_seconds"):
            return int(act["recommended_poll_seconds"])
        if quota.get("recommended_poll_seconds"):
            return int(quota["recommended_poll_seconds"])
    return 30

def activity_fingerprint(act):
    if not isinstance(act, dict):
        return ""
    parts = [str(act.get("overall_status", "")), str(act.get("recommended_poll_seconds", ""))]
    provs = act.get("providers") if isinstance(act.get("providers"), dict) else {}
    for k in ("antigravity", "claude_pro", "chatgpt_subscription", "cursor", "github_copilot"):
        item = provs.get(k)
        if isinstance(item, dict):
            parts.append(f"{k}:{item.get('status', '')}:{item.get('detail', '')}")
    return "|".join(parts)

def format_activity_tooltip(title, act, poll_secs):
    st = (act.get("status") if isinstance(act, dict) else None) or "idle"
    status_txt = "Working" if st == "working" else ("Waiting for input" if st == "waiting" else "Idle")
    poll_lbl = "5 min (idle)" if poll_secs >= 300 else f"{poll_secs}s (active)"
    lines = [f"{title} · {status_txt}"]
    if isinstance(act, dict):
        det = (act.get("detail") or "").strip()
        proj = (act.get("project") or "").strip()
        if det:
            lines.append(det)
        elif proj:
            lines.append(f"Project: {proj}")
        age = act.get("age_seconds")
        if age is not None and st != "idle":
            lines.append(f"Updated {age}s ago · Polling: {poll_lbl}")
            return "\n".join(lines)
    lines.append(f"Polling: {poll_lbl}")
    return "\n".join(lines)

PASTEL_PALETTE = [
    ("Sky Blue", "#8FBCFF"),
    ("Mint", "#8AE39A"),
    ("Coral", "#FF5265"),
    ("Terracotta", "#D78C68"),
    ("Lavender", "#C084FC"),
    ("Cyan", "#67E8F9"),
]

PASTEL_DEFAULTS = {
    "antigravity": "#8FBCFF",
    "claude_pro": "#D78C68",
    "chatgpt_subscription": "#8AE39A",
    "cursor": "#C084FC",
    "github_copilot": "#FF5265",
    "gemini": "#67E8F9",
    "openai": "#8AE39A",
    "anthropic": "#D78C68",
}

def get_provider_key(group_name, provider_name):
    gn = (group_name or "").lower()
    pn = (provider_name or "").lower()
    if "antigravity" in pn or "antigravity" in gn or "claude and gpt" in gn or "argon" in gn:
        return "antigravity"
    if "cursor" in pn or "cursor" in gn:
        return "cursor"
    if "copilot" in pn or "copilot" in gn or "github" in pn:
        return "github_copilot"
    if "chatgpt" in pn or "chatgpt" in gn:
        return "chatgpt_subscription"
    if "claude" in pn or "claude" in gn:
        return "claude_pro"
    if "studio" in pn or "gemini" in pn or "gemini" in gn:
        return "gemini"
    if "openai" in pn or "openai" in gn:
        return "openai"
    if "anthropic" in pn or "anthropic" in gn:
        return "anthropic"
    return "antigravity"

def get_section_clean_title(prov_key, fallback_name=""):
    return {
        "antigravity": "Antigravity",
        "claude_pro": "Claude",
        "chatgpt_subscription": "ChatGPT",
        "cursor": "Cursor",
        "github_copilot": "Copilot",
        "gemini": "Gemini",
        "openai": "OpenAI",
        "anthropic": "Anthropic",
    }.get(prov_key, fallback_name or "AI")

def get_bucket_window_label(bucket_name, bucket_id):
    s = f"{bucket_name or ''} {bucket_id or ''}".lower()
    if "5h" in s or "5 hour" in s or "five" in s:
        return "5 HOURS"
    if "3h" in s or "3 hour" in s:
        return "3 HOURS"
    if "weekly" in s or "7d" in s or "semanal" in s:
        return "WEEKLY"
    if "month" in s or "mensal" in s or "ciclo" in s:
        return "MONTHLY"
    if "fast" in s:
        return "FAST REQS"
    if "flash" in s:
        return "FLASH RPM"
    if "pro" in s:
        return "PRO RPM"
    if "tpm" in s or "token" in s:
        return "TPM LIMIT"
    if "rate" in s or "rpm" in s:
        return "RATE LIMIT"
    if "chat" in s:
        return "CHAT LIMIT"
    if "key" in s or "status" in s:
        return "API KEY"
    return "QUOTA"

def get_bucket_model_name(bucket_name, group_name):
    bn = (bucket_name or "").strip()
    gn = (group_name or "").strip()
    bl = bn.lower()
    gl = gn.lower()
    if ("claude" in bl and "gpt" in bl) or ("claude" in gl and "gpt" in gl):
        return "Claude/GPT"
    if "argon" in bl or "argon" in gl:
        return "Argon"
    if "gpt-4o" in bl:
        return "GPT-4o"
    if "o1" in bl:
        return "o1"
    if "gemini" in bl:
        return "Gemini"
    if "claude" in bl:
        return "Claude"
    if "gemini" in gl:
        return "Gemini"
    if "claude" in gl:
        return "Claude"
    if "chatgpt" in gl:
        return "ChatGPT"
    if "cursor" in gl:
        return "Cursor"
    if "copilot" in gl:
        return "Copilot"
    if "openai" in gl:
        return "OpenAI"
    if "anthropic" in gl:
        return "Anthropic"
    return bn[:14]

def get_hud_sections(quota):
    cfg = load_config()
    hidden_set = set(cfg.get("hidden_hud_gauges", []))
    sec_colors = cfg.get("section_colors", {})
    order = []
    sec_map = {}

    for g in (quota or {}).get("groups", []):
        gname = g.get("name", "")
        prov = g.get("provider", "")
        visible = [b for b in g.get("buckets", []) if (b.get("id") or b.get("name")) not in hidden_set]
        if not visible:
            continue
        pk = get_provider_key(gname, prov)
        if pk not in sec_map:
            accent = sec_colors.get(pk) or PASTEL_DEFAULTS.get(pk, "#8FBCFF")
            sec_obj = {
                "key": pk,
                "title": get_section_clean_title(pk, gname),
                "accent": accent,
                "activity": get_provider_activity(quota, pk) or g.get("activity"),
                "items": [],
            }
            sec_map[pk] = sec_obj
            order.append(sec_obj)
        accent = sec_map[pk]["accent"]
        for b in visible:
            bid = b.get("id", "")
            bname = b.get("name", "")
            sec_map[pk]["items"].append({
                "id": bid,
                "title": get_bucket_window_label(bname, bid),
                "model": get_bucket_model_name(bname, gname),
                "pct": b.get("remaining_pct", 100),
                "reset_in": b.get("reset_in", ""),
                "detail": b.get("detail", ""),
                "provider": prov,
                "accent": accent,
            })
    return order

def get_gauge_items(quota):
    items = []
    for sec in get_hud_sections(quota):
        items.extend(sec["items"])
    return items

def status_color(pct, custom_accent=None):
    if pct <= 15:
        return "#FF4D4F"
    if pct <= 30:
        return "#F5A623"
    return custom_accent if custom_accent else "#8FBCFF"

def print_cli(quota):
    app_ver = get_app_version(quota)
    if not quota or quota.get("needs_setup"):
        print("\n" + "="*58)
        print(f" ⚡ AI Gauge v{app_ver} - Setup Required")
        print("="*58)
        print(" No active or configured AI provider.")
        print(f" Configure your keys in: {CONFIG_FILE}")
        print(" Example: add GEMINI_API_KEY or OPENAI_API_KEY.")
        print("="*58 + "\n")
        return

    poll_secs = get_effective_poll_seconds(quota)
    poll_label = "5 min (idle)" if poll_secs >= 300 else f"{poll_secs}s (active)"
    print("\n" + "="*58)
    print(f" ⚡ AI Gauge v{app_ver} - vh2c.com.br")
    print(f" Account: {quota.get('account', 'Multi-Provider')} • Plan {quota.get('plan', 'Universal')}")
    print(f" Updated at {quota.get('updated_at', 'now')} " + ("(Live)" if not quota.get("from_cache") else "(Cache)") + f" · Polling {poll_label}")
    print("="*58)

    for g in quota.get("groups", []):
        prov = f" [{g.get('provider')}]" if g.get('provider') else ""
        pk = get_provider_key(g.get("name", ""), g.get("provider", ""))
        act = get_provider_activity(quota, pk) or g.get("activity") or {}
        st = (act.get("status") or "idle").lower()
        det = (act.get("detail") or "").strip()
        if st == "working":
            st_badge = f" \033[96m[WORKING{(' · ' + det) if det else ''}]\033[0m"
        elif st == "waiting":
            st_badge = f" \033[93m[WAITING{(' · ' + det) if det else ''}]\033[0m"
        else:
            st_badge = " \033[90m[IDLE]\033[0m"
        print(f"\n📂 {g.get('name', 'Group').upper()}{prov}{st_badge}")
        for b in g.get("buckets", []):
            pct = b.get("remaining_pct", 0)
            reset = f" • {b.get('reset_in')}" if b.get("reset_in") else ""
            bar_len = 24
            filled = int(round(bar_len * pct / 100))
            bar = "█" * filled + "░" * (bar_len - filled)
            col = "\033[92m" if pct > 50 else ("\033[93m" if pct > 20 else "\033[91m")
            rst = "\033[0m"
            print(f"  {b.get('name', 'Limit'):<26} {col}{pct:>3}%{rst}{reset}")
            print(f"  [{col}{bar}{rst}]")
    print("\n" + "="*58 + "\n")

try:
    import tkinter as tk
    HAS_TK = True
except ImportError:
    HAS_TK = False

def make_flat_button(parent, text, fg="#181818", bg="#EEEEF0", hover_bg=None, font=("Sans", 9, "bold"), padx=10, pady=5, command=None, width=None):
    kw = {
        "text": text,
        "font": font,
        "fg": fg,
        "bg": bg,
        "activebackground": hover_bg or bg,
        "activeforeground": fg,
        "bd": 0,
        "highlightthickness": 0,
        "relief": "flat",
        "takefocus": 0,
        "padx": padx,
        "pady": pady,
        "cursor": "hand2",
    }
    if width is not None:
        kw["width"] = width
    if command is not None:
        kw["command"] = command
    btn = tk.Button(parent, **kw)
    if hover_bg:
        btn.bind("<Enter>", lambda _e, b=btn, hb=hover_bg: b.config(bg=hb) if str(b.cget("state")) != "disabled" else None)
        btn.bind("<Leave>", lambda _e, b=btn, ob=bg: b.config(bg=ob) if str(b.cget("state")) != "disabled" else None)
    return btn

def bind_mousewheel_scroll(widget, canvas):
    def _scroll(event):
        try:
            if not canvas.winfo_exists():
                return
            if getattr(event, "num", None) == 4:
                canvas.yview_scroll(-1, "units")
            elif getattr(event, "num", None) == 5:
                canvas.yview_scroll(1, "units")
            elif getattr(event, "delta", 0):
                canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")
        except Exception:
            pass
    for ev in ("<MouseWheel>", "<Button-4>", "<Button-5>"):
        widget.bind(ev, _scroll, add="+")
    return _scroll

class ModernCheckbox(tk.Frame):
    """Canvas-drawn dark checkbox with zero X11 light-gray focus/highlight ring."""
    def __init__(self, parent, text, variable, fg="#FFFFFF", bg="#1E1E22", accent="#00E699", font=("Sans", 9, "bold"), command=None):
        super().__init__(parent, bg=bg, bd=0, highlightthickness=0)
        self.variable = variable
        self.accent = accent
        self.bg_col = bg
        self.fg_col = fg
        self.command = command
        self.hovered = False
        self.enabled = True

        self.box = tk.Canvas(self, width=16, height=16, bg=bg, bd=0, highlightthickness=0, cursor="hand2")
        self.box.pack(side="left", padx=(0, 7))
        self.lbl = tk.Label(self, text=text, font=font, fg=fg, bg=bg, bd=0, cursor="hand2")
        self.lbl.pack(side="left")

        for w in (self, self.box, self.lbl):
            w.bind("<Button-1>", self._toggle)
            w.bind("<Enter>", self._on_enter)
            w.bind("<Leave>", self._on_leave)
        self.draw()

    def _on_enter(self, _e=None):
        self.hovered = True
        self.draw()

    def _on_leave(self, _e=None):
        self.hovered = False
        self.draw()

    def set_enabled(self, flag: bool):
        self.enabled = bool(flag)
        self.lbl.config(fg=self.fg_col if self.enabled else "#64748B")
        self.draw()

    def _toggle(self, _e=None):
        if not self.enabled:
            return
        self.variable.set(not bool(self.variable.get()))
        self.draw()
        if self.command:
            self.command()

    def draw(self):
        c = self.box
        c.delete("all")
        checked = bool(self.variable.get())
        if checked:
            fill = self.accent
            border = "#FFFFFF" if self.hovered else self.accent
            c.create_rectangle(1, 1, 14, 14, fill=fill, outline=border, width=1)
            c.create_line(4, 8, 7, 11, 12, 5, fill="#121214", width=2, capstyle="round", joinstyle="round")
        else:
            fill = "#303642" if self.hovered else "#222630"
            border = "#CBD5E1" if self.hovered else "#64748B"
            c.create_rectangle(1, 1, 14, 14, fill=fill, outline=border, width=1.4)

class QuotaHubAppLinux:
    def __init__(self):
        self.root = tk.Tk()
        self.root.option_add("*highlightThickness", 0)
        self.root.option_add("*BorderWidth", 0)
        self.root.title("AI Gauge - Universal AI Quota Cockpit")
        self.root.configure(bg="#181818")
        self._wm_overrideredirect = None
        self._hud_pos = None

        # Load App Icon
        icon_candidates = [
            APP_DIR / "icon.png",
            REPO_ROOT / "assets" / "icon.png",
            Path.home() / ".local" / "share" / "universal-ai-quota" / "icon.png"
        ]
        self._icon_img = None
        for ic in icon_candidates:
            if ic.exists():
                try:
                    self._icon_img = tk.PhotoImage(file=str(ic))
                    self.root.iconphoto(True, self._icon_img)
                    break
                except Exception:
                    pass

        self.prefs = {}
        if PREFS_FILE.exists():
            try:
                with open(PREFS_FILE, "r") as f:
                    self.prefs = json.load(f)
            except Exception:
                pass
        self.mode = self.prefs.get("mode", "full")
        self.orientation = self.prefs.get("orientation", "vertical")
        self.settings_dlg = None
        self.app_started_at = time.time()
        self.promo_last_shown_at = 0.0
        self.promo_scheduled = False
        self.promo_window = None
        self.promo_photo = None
        self.promo_countdown_job = None

        if "--hud" in sys.argv:
            self.mode = "hud"
        if "--vertical" in sys.argv:
            self.orientation = "vertical"
        if "--horizontal" in sys.argv:
            self.orientation = "horizontal"
        if "--full" in sys.argv:
            self.mode = "full"

        # Fast startup: read cache first if available (instant), otherwise start empty
        self.quota = None
        if CACHE_FILE.exists():
            try:
                with open(CACHE_FILE, "r", encoding="utf-8") as f:
                    self.quota = reconcile_update(json.load(f))
            except Exception:
                pass

        self.is_refreshing = False
        self.poll_interval_ms = get_effective_poll_seconds(self.quota) * 1000
        self.last_quota_fetch_at = 0.0
        self._auto_refresh_job = None
        self._activity_probe_job = None
        self._anim_job = None
        self._anim_phase = 0
        self._anim_targets = []
        self._tooltip_win = None
        self._tooltip_text = None
        self._hud_idle_since = None
        self._hud_manual_override = False
        self._hud_peek_win = None
        self._is_hovering_hud = False
        self._hud_hover_reveal_until = 0.0
        self._hud_hide_job = None
        self._is_hud_fading = False

        self.root.bind("<Enter>", self._on_hud_enter)
        self.root.bind("<Leave>", self._on_hud_leave)

        self.root.bind("<Control-m>", lambda e: self.toggle_mode())
        self.root.bind("<Control-M>", lambda e: self.toggle_mode())
        self.root.bind("<Control-o>", lambda e: self.toggle_orientation())
        self.root.bind("<Control-O>", lambda e: self.toggle_orientation())
        self.root.bind("<Control-r>", lambda e: self.refresh(True))
        self.root.bind("<Control-R>", lambda e: self.refresh(True))
        self.root.bind("<F5>", lambda e: self.refresh(True))
        self.root.bind("<Escape>", lambda e: self.root.destroy())

        self.setup_ui()
        self.schedule_auto_refresh()
        self.schedule_activity_probe()

        # Lift window and bring to front on Linux desktop
        try:
            self.root.deiconify()
            self.root.lift()
            self.root.focus_force()
        except Exception:
            pass

        # Trigger background refresh
        self.refresh(animated=(self.quota is None))

    def save_prefs(self):
        self.prefs["mode"] = self.mode
        self.prefs["orientation"] = self.orientation
        try:
            with open(PREFS_FILE, "w") as f:
                json.dump(self.prefs, f)
        except Exception:
            pass

    def schedule_auto_refresh(self):
        if self._auto_refresh_job is not None:
            try:
                self.root.after_cancel(self._auto_refresh_job)
            except Exception:
                pass
            self._auto_refresh_job = None
        self._auto_refresh_job = self.root.after(self.poll_interval_ms, self.auto_refresh)

    def auto_refresh(self):
        self._auto_refresh_job = None
        # Do not refresh or rebuild UI while the user is actively configuring settings
        if not (self.settings_dlg and self.settings_dlg.winfo_exists()):
            self.refresh(animated=False)
        self.schedule_auto_refresh()

    def schedule_activity_probe(self):
        if self._activity_probe_job is not None:
            try:
                self.root.after_cancel(self._activity_probe_job)
            except Exception:
                pass
            self._activity_probe_job = None
        self._activity_probe_job = self.root.after(10000, self._run_activity_probe)

    def _run_activity_probe(self):
        self._activity_probe_job = None
        if (
            not DEMO_MODE
            and not self.is_refreshing
            and self.quota is not None
            and not (self.settings_dlg and self.settings_dlg.winfo_exists())
        ):
            def worker():
                act = load_activity_only()
                if act:
                    try:
                        self.root.after(0, lambda a=act: self._on_activity_probed(a))
                    except Exception:
                        pass
            threading.Thread(target=worker, daemon=True).start()
        self.schedule_activity_probe()

    def _on_activity_probed(self, act):
        if not isinstance(self.quota, dict) or not isinstance(act, dict):
            return
        prev_fp = activity_fingerprint(self.quota.get("activity"))
        next_fp = activity_fingerprint(act)
        self.quota["activity"] = act
        if act.get("recommended_poll_seconds"):
            self.quota["recommended_poll_seconds"] = act["recommended_poll_seconds"]
        next_ms = get_effective_poll_seconds(self.quota) * 1000
        if next_ms != self.poll_interval_ms:
            self.poll_interval_ms = next_ms
            self.schedule_auto_refresh()
        if prev_fp != next_fp and not (self.settings_dlg and self.settings_dlg.winfo_exists()):
            self.setup_ui()
        else:
            self._apply_hud_auto_hide_policy()
        if act.get("transition_to_idle") or act.get("transition_to_active"):
            self.refresh(animated=False)

    def refresh(self, animated=True):
        if self.is_refreshing:
            return
        self.is_refreshing = True
        if animated and getattr(self, "refresh_btn", None) is not None:
            try:
                if self.refresh_btn.winfo_exists():
                    self.refresh_btn.config(text="Refreshing...")
                    self.root.update_idletasks()
            except Exception:
                pass

        def do_fetch():
            new_data = load_quota(force=True)
            try:
                self.root.after(0, lambda: self.on_fetched(new_data))
            except Exception:
                pass

        threading.Thread(target=do_fetch, daemon=True).start()

    def _apply_window_chrome(self, borderless: bool, topmost: bool):
        try:
            self.root.attributes("-topmost", bool(topmost))
        except Exception:
            pass
        if self._wm_overrideredirect != borderless:
            self._wm_overrideredirect = borderless
            try:
                self.root.withdraw()
                self.root.overrideredirect(borderless)
                self.root.update_idletasks()
                self.root.deiconify()
                self.root.lift()
            except Exception:
                try:
                    self.root.overrideredirect(borderless)
                except Exception:
                    pass

    def on_fetched(self, data):
        self.is_refreshing = False
        if data:
            self.last_quota_fetch_at = time.time()
            self.quota = data
            next_ms = get_effective_poll_seconds(data) * 1000
            if next_ms != self.poll_interval_ms:
                self.poll_interval_ms = next_ms
                self.schedule_auto_refresh()
            # If settings window is currently open, don't interrupt user typing
            if not (self.settings_dlg and self.settings_dlg.winfo_exists()):
                self.setup_ui()
            else:
                self.check_and_schedule_promo()

    def close_promo_toast(self):
        if self.promo_countdown_job:
            try:
                self.root.after_cancel(self.promo_countdown_job)
            except Exception:
                pass
            self.promo_countdown_job = None
        if self.promo_window:
            try:
                self.promo_window.destroy()
            except Exception:
                pass
            self.promo_window = None
        self.promo_photo = None

    def check_and_schedule_promo(self):
        quota = self.quota if isinstance(self.quota, dict) else {}
        tier = (quota.get("tier") or "free").lower()
        promo = quota.get("promo")
        ann = quota.get("announcement")
        if not promo and isinstance(ann, dict) and (ann.get("type") or "").lower() == "publicidade":
            promo = ann
        if not isinstance(promo, dict) or not (promo.get("title") or promo.get("message")):
            return
        if tier in ("pro", "enterprise") and not quota.get("promo"):
            return
        if self.promo_window and self.promo_window.winfo_exists():
            return
        if self.promo_scheduled:
            return

        now = time.time()
        interval_seconds = 6 * 3600.0
        if self.promo_last_shown_at > 0 and (now - self.promo_last_shown_at) < interval_seconds:
            return

        if self.promo_last_shown_at == 0:
            initial_delay = 6.0 if DEMO_MODE else 60.0
            wait_s = max(0.2, initial_delay - (now - self.app_started_at))
        else:
            wait_s = 0.2

        self.promo_scheduled = True
        self.root.after(int(wait_s * 1000), lambda p=promo: self._trigger_promo_toast(p))

    def _trigger_promo_toast(self, fallback_promo):
        self.promo_scheduled = False
        quota = self.quota if isinstance(self.quota, dict) else {}
        promo = quota.get("promo")
        ann = quota.get("announcement")
        if not promo and isinstance(ann, dict) and (ann.get("type") or "").lower() == "publicidade":
            promo = ann
        if not promo:
            promo = fallback_promo
        if not isinstance(promo, dict):
            return

        self.promo_last_shown_at = time.time()
        self.show_promo_toast(promo)
        self.root.after(int(6 * 3600 * 1000), self.check_and_schedule_promo)

    def _download_promo_image_payload(self, url_str, target_w=348, target_h=160):
        """Worker-thread helper: NEVER calls tk/ImageTk (must run strictly on main Tk thread)."""
        if not url_str:
            return None
        if url_str.startswith("http://"):
            url_str = "https://" + url_str[7:]
        tmp_raw = None
        tmp_png = None
        try:
            req = urllib.request.Request(url_str, headers={"User-Agent": "AIGauge/1.2"})
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = resp.read()
            if not data:
                return None

            try:
                from PIL import Image
                import io
                img = Image.open(io.BytesIO(data)).convert("RGB")
                iw, ih = img.size
                if iw > 0 and ih > 0:
                    scale = max(target_w / float(iw), target_h / float(ih))
                    nw, nh = max(1, int(iw * scale)), max(1, int(ih * scale))
                    img = img.resize((nw, nh), Image.LANCZOS)
                    left = max(0, (nw - target_w) // 2)
                    top = max(0, (nh - target_h) // 2)
                    img = img.crop((left, top, left + target_w, top + target_h))
                return ("pil", img, None)
            except Exception:
                pass

            fd, tmp_raw = tempfile.mkstemp(prefix="aigauge_promo_")
            os.close(fd)
            with open(tmp_raw, "wb") as f:
                f.write(data)

            if url_str.lower().split("?")[0].endswith(".png"):
                return ("file", tmp_raw, tmp_raw)

            tmp_png = tmp_raw + ".png"
            conv = shutil.which("convert") or shutil.which("magick")
            ffm = shutil.which("ffmpeg")
            if conv:
                subprocess.run([conv, tmp_raw, "-resize", f"{target_w}x{target_h}^", "-gravity", "center", "-extent", f"{target_w}x{target_h}", tmp_png],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            elif ffm:
                subprocess.run([ffm, "-y", "-i", tmp_raw, "-vf", f"scale={target_w}:{target_h}:force_original_aspect_ratio=increase,crop={target_w}:{target_h}", tmp_png],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            try:
                os.remove(tmp_raw)
            except Exception:
                pass
            if os.path.exists(tmp_png):
                return ("file", tmp_png, tmp_png)
        except Exception:
            for p in (tmp_raw, tmp_png):
                if p and os.path.exists(p):
                    try:
                        os.remove(p)
                    except Exception:
                        pass
        return None

    def show_promo_toast(self, promo):
        self.close_promo_toast()
        win = tk.Toplevel(self.root)
        self.promo_window = win
        win.title("AI Gauge")
        win.overrideredirect(True)
        win.attributes("-topmost", True)
        win.configure(bg="#2E2E3A")

        card = tk.Frame(win, bg="#16171F", padx=16, pady=14)
        card.pack(fill="both", expand=True, padx=1, pady=1)

        top = tk.Frame(card, bg="#16171F")
        top.pack(fill="x")
        tk.Label(top, text="⚡ AI GAUGE - PROMOTION", font=("Sans", 8, "bold"), fg="#94A3B8", bg="#16171F").pack(side="left")
        btn_x = make_flat_button(top, "✕", fg="#64748B", bg="#16171F", hover_bg="#222330",
                                 font=("Sans", 9, "bold"), padx=6, pady=1, command=self.close_promo_toast)
        btn_x.pack(side="right")

        media_holder = tk.Frame(card, bg="#16171F")
        media_holder.pack(fill="x")

        title_str = (promo.get("title") or "AI Gauge Pro").strip()
        msg_str = (promo.get("message") or "").strip()

        tk.Label(card, text=title_str, font=("Sans", 13, "bold"), fg="#FFFFFF", bg="#16171F",
                 anchor="w", justify="left", wraplength=346).pack(fill="x", pady=(10, 4))
        tk.Label(card, text=msg_str, font=("Sans", 10), fg="#94A3B8", bg="#16171F",
                 anchor="w", justify="left", wraplength=346).pack(fill="x", pady=(0, 14))

        btns = tk.Frame(card, bg="#16171F")
        btns.pack(fill="x")

        rem = [int(promo.get("duracao_segundos") or 0)]
        btn_later = make_flat_button(btns, "Not now", fg="#E2E8F0", bg="#262835", hover_bg="#323546",
                                     font=("Sans", 10, "bold"), padx=10, pady=7,
                                     command=lambda: None if rem[0] > 0 else self.close_promo_toast())

        act_url = (promo.get("action_url") or "").strip()
        if act_url:
            if "{machine_id}" in act_url:
                act_url = act_url.replace("{machine_id}", get_machine_id())
            act_label = (promo.get("action_label") or "View Details").strip() or "View Details"
            btn_later.pack(side="left", fill="x", expand=True, padx=(0, 5))
            btn_act = make_flat_button(btns, act_label, fg="#FFFFFF", bg="#4F46E5", hover_bg="#6366F1",
                                       font=("Sans", 10, "bold"), padx=10, pady=7,
                                       command=lambda u=act_url: (webbrowser.open(u), self.close_promo_toast()))
            btn_act.pack(side="left", fill="x", expand=True, padx=(5, 0))
        else:
            btn_later.pack(fill="x", expand=True)

        if rem[0] > 0:
            btn_later.config(state="disabled", text=f"Not now ({rem[0]}s)")
            def tick():
                if not (self.promo_window and self.promo_window.winfo_exists()):
                    return
                rem[0] -= 1
                if rem[0] <= 0:
                    btn_later.config(state="normal", text="Not now")
                else:
                    btn_later.config(text=f"Not now ({rem[0]}s)")
                    self.promo_countdown_job = self.root.after(1000, tick)
            self.promo_countdown_job = self.root.after(1000, tick)

        def position_toast():
            if not (self.promo_window and self.promo_window.winfo_exists()):
                return
            win.update_idletasks()
            tw = 382
            th = max(win.winfo_reqheight(), 190)
            sw = self.root.winfo_screenwidth()
            sh = self.root.winfo_screenheight()
            px = max(16, sw - tw - 18)
            py = max(16, sh - th - 48)
            win.geometry(f"{tw}x{th}+{px}+{py}")
            win.lift()
            win.attributes("-topmost", True)

        position_toast()

        img_url = (promo.get("image_url") or "").strip()
        if img_url:
            def fetch_img():
                payload = self._download_promo_image_payload(img_url)
                if not payload:
                    return
                def apply_img():
                    kind, obj, cleanup_path = payload
                    try:
                        if not (self.promo_window and self.promo_window.winfo_exists()):
                            return
                        if kind == "pil":
                            from PIL import ImageTk
                            photo = ImageTk.PhotoImage(obj)
                        else:
                            photo = tk.PhotoImage(file=obj)
                        self.promo_photo = photo
                        lbl_img = tk.Label(media_holder, image=photo, bg="#0E1015", bd=0)
                        lbl_img.pack(pady=(10, 0))
                        position_toast()
                    except Exception:
                        pass
                    finally:
                        if cleanup_path and os.path.exists(cleanup_path):
                            try:
                                os.remove(cleanup_path)
                            except Exception:
                                pass
                try:
                    self.root.after(0, apply_img)
                except Exception:
                    pass
            threading.Thread(target=fetch_img, daemon=True).start()

    def toggle_mode(self):
        self.mode = "hud" if self.mode == "full" else "full"
        self._hud_idle_since = None
        self._hud_manual_override = False
        self._hud_peek_win = None
        self._is_hovering_hud = False
        self._hud_hover_reveal_until = 0.0
        self._hud_hide_job = None
        self._is_hud_fading = False

        self.root.bind("<Enter>", self._on_hud_enter)
        self.root.bind("<Leave>", self._on_hud_leave)
        self.save_prefs()
        self.setup_ui()
        if self.mode == "full" and (time.time() - self.last_quota_fetch_at) > 15:
            self.refresh(animated=False)

    def toggle_orientation(self):
        self.orientation = "horizontal" if self.orientation == "vertical" else "vertical"
        self.save_prefs()
        self.setup_ui()

    def open_settings(self):
        if self.settings_dlg and self.settings_dlg.winfo_exists():
            self.settings_dlg.lift()
            self.settings_dlg.focus_force()
            return

        cfg = load_config()
        pCfg = cfg.get("providers", {})
        hidden_set = set(cfg.get("hidden_hud_gauges", []))
        saved_colors = dict(cfg.get("section_colors", {}))
        sec_colors_state = {k: saved_colors.get(k, PASTEL_DEFAULTS[k]) for k in PASTEL_DEFAULTS}

        dlg = tk.Toplevel(self.root)
        self.settings_dlg = dlg
        dlg.option_add("*highlightThickness", 0)
        dlg.title("Settings - AI Gauge")
        dlg.geometry("520x640")
        dlg.configure(bg="#181818")
        dlg.transient(self.root)
        dlg.grab_set()

        def close_dlg():
            self.settings_dlg = None
            try:
                dlg.destroy()
            except Exception:
                pass
        dlg.protocol("WM_DELETE_WINDOW", close_dlg)

        header = tk.Label(dlg, text="Settings - AI Providers & Gauges", font=("Sans", 11, "bold"), fg="#FFFFFF", bg="#181818", anchor="w")
        header.pack(fill="x", pady=(14, 2), padx=18)

        sub = tk.Label(dlg, text="Enable providers, verify API keys and customize section colors:", font=("Sans", 8), fg="#8C8C96", bg="#181818", anchor="w")
        sub.pack(fill="x", padx=18, pady=(0, 10))

        tk.Frame(dlg, bg="#28282E", height=1).pack(fill="x", padx=18)

        # Bottom buttons bar (packed first with side="bottom" to guarantee visibility)
        f_btns = tk.Frame(dlg, bg="#181818", padx=18, pady=12)
        f_btns.pack(fill="x", side="bottom")

        # Canvas with scrollbar for cards
        c_frame = tk.Frame(dlg, bg="#181818")
        c_frame.pack(fill="both", expand=True, padx=14, pady=6)
        c_canvas = tk.Canvas(c_frame, bg="#181818", highlightthickness=0, bd=0)
        c_scrollbar = tk.Scrollbar(c_frame, orient="vertical", command=c_canvas.yview, bg="#202026", troughcolor="#141418", bd=0, highlightthickness=0)
        cards_box = tk.Frame(c_canvas, bg="#181818")
        cards_box.bind("<Configure>", lambda e: c_canvas.configure(scrollregion=c_canvas.bbox("all")))
        c_canvas.create_window((0, 0), window=cards_box, anchor="nw", width=472)
        c_canvas.configure(yscrollcommand=c_scrollbar.set)
        c_canvas.pack(side="left", fill="both", expand=True)
        c_scrollbar.pack(side="right", fill="y")
        bind_mousewheel_scroll(dlg, c_canvas)

        def make_card(border_col="#2C2C30"):
            card = tk.Frame(cards_box, bg="#1E1E22", padx=12, pady=10, highlightbackground=border_col, highlightthickness=1, bd=0)
            card.pack(fill="x", pady=5)
            return card

        def make_dark_entry(parent, value="", show="•"):
            wrap = tk.Frame(parent, bg="#141418", highlightbackground="#2E2E38", highlightthickness=1, bd=0, padx=6, pady=4)
            ent = tk.Entry(wrap, font=("Sans", 8), bg="#141418", fg="#FFFFFF", insertbackground="#FFFFFF",
                           bd=0, highlightthickness=0, relief="flat", show=show)
            if value:
                ent.insert(0, value)
            ent.pack(fill="x", expand=True)
            return wrap, ent

        def add_card_header(parent, title, var_chk, prov_key, title_col="#FFFFFF"):
            row = tk.Frame(parent, bg="#1E1E22")
            row.pack(fill="x")
            ModernCheckbox(row, text=title, variable=var_chk, fg=title_col, bg="#1E1E22", font=("Sans", 9, "bold")).pack(side="left")
            swatch_bar = tk.Frame(row, bg="#1E1E22")
            swatch_bar.pack(side="right")
            swatch_canvases = []

            def redraw_swatches():
                active = (sec_colors_state.get(prov_key) or PASTEL_DEFAULTS[prov_key]).upper()
                for sc, shex in swatch_canvases:
                    sc.delete("all")
                    is_sel = (shex.upper() == active)
                    sc.create_oval(2, 2, 13, 13, fill=shex, outline="#FFFFFF" if is_sel else "#2E2E38", width=2 if is_sel else 1)

            for _sname, shex in PASTEL_PALETTE:
                sc = tk.Canvas(swatch_bar, width=15, height=15, bg="#1E1E22", bd=0, highlightthickness=0, cursor="hand2")
                sc.pack(side="left", padx=2)
                sc.bind("<Button-1>", lambda _e, pk=prov_key, hx=shex: (sec_colors_state.__setitem__(pk, hx), redraw_swatches()))
                swatch_canvases.append((sc, shex))
            redraw_swatches()

        hud_vars = {}
        def add_hud_cb(parent, gid, label):
            v = tk.BooleanVar(value=(gid not in hidden_set))
            hud_vars[gid] = v
            cb = ModernCheckbox(parent, text=label, variable=v, fg="#CBD5E1", bg="#1E1E22", font=("Sans", 8))
            cb.pack(side="left", padx=(0, 12))

        # 0. HUD Side Bar Behavior Card
        f_hud_beh = make_card()
        tk.Label(f_hud_beh, text="HUD Side Bar Behavior", font=("Sans", 8, "bold"), fg="#A1A1AA", bg="#1E1E22").pack(anchor="w", pady=(0, 6))
        var_hud_auto_hide = tk.BooleanVar(value=bool(cfg.get("hud_auto_hide", False)))
        var_hud_show_on_activity = tk.BooleanVar(value=bool(cfg.get("hud_show_on_activity", True)))
        cb_hud_show_on_activity = None

        def on_hud_auto_hide_toggle():
            if cb_hud_show_on_activity is not None:
                cb_hud_show_on_activity.set_enabled(bool(var_hud_auto_hide.get()))

        cb_hud_auto_hide = ModernCheckbox(
            f_hud_beh,
            text="Auto-hide HUD when idle",
            variable=var_hud_auto_hide,
            fg="#FFFFFF",
            bg="#1E1E22",
            font=("Sans", 9, "bold"),
            command=on_hud_auto_hide_toggle,
        )
        cb_hud_auto_hide.pack(anchor="w")
        r_hud_sub = tk.Frame(f_hud_beh, bg="#1E1E22")
        r_hud_sub.pack(anchor="w", padx=(18, 0), pady=(5, 0))
        cb_hud_show_on_activity = ModernCheckbox(
            r_hud_sub,
            text="Show HUD automatically while an agent is working or waiting",
            variable=var_hud_show_on_activity,
            fg="#CBD5E1",
            bg="#1E1E22",
            font=("Sans", 8),
        )
        cb_hud_show_on_activity.pack(anchor="w")
        cb_hud_show_on_activity.set_enabled(bool(var_hud_auto_hide.get()))

        # 1. Antigravity Card
        f_anti = make_card()
        var_anti = tk.BooleanVar(value=pCfg.get("antigravity", {}).get("enabled", True))
        add_card_header(f_anti, "Antigravity IDE", var_anti, "antigravity")
        tk.Label(f_anti, text="Detects quotas from running IDE or headless probe.", font=("Sans", 7), fg="#8C8C96", bg="#1E1E22").pack(anchor="w", pady=(3, 0))
        tk.Label(f_anti, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#8C8C96", bg="#1E1E22").pack(anchor="w", pady=(5, 3))
        r_anti1 = tk.Frame(f_anti, bg="#1E1E22")
        r_anti1.pack(anchor="w")
        add_hud_cb(r_anti1, "gemini-weekly", "Gemini Weekly")
        add_hud_cb(r_anti1, "gemini-5h", "Gemini (5h)")
        add_hud_cb(r_anti1, "gemini-argon-wtu-weekly", "Argon")
        r_anti2 = tk.Frame(f_anti, bg="#1E1E22")
        r_anti2.pack(anchor="w", pady=(4, 0))
        add_hud_cb(r_anti2, "3p-weekly", "Claude/GPT Weekly")
        add_hud_cb(r_anti2, "3p-5h", "Claude/GPT (5h)")

        # 2. Claude Pro Card
        cpro_cfg = pCfg.get("claude_pro", {})
        f_cpro = make_card()
        var_claude_pro = tk.BooleanVar(value=cpro_cfg.get("enabled", True))
        add_card_header(f_cpro, "Claude (Pro / Code)", var_claude_pro, "claude_pro", title_col="#D78C68")
        wrap_cpro, ent_claude_token = make_dark_entry(f_cpro, cpro_cfg.get("token", ""))
        wrap_cpro.pack(fill="x", pady=(6, 3))
        tk.Label(f_cpro, text="Optional OAuth token (auto-detected if signed in)", font=("Sans", 7), fg="#8C8C96", bg="#1E1E22").pack(anchor="w")
        tk.Label(f_cpro, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#D78C68", bg="#1E1E22").pack(anchor="w", pady=(5, 3))
        r_cpro = tk.Frame(f_cpro, bg="#1E1E22")
        r_cpro.pack(anchor="w")
        add_hud_cb(r_cpro, "claude-pro-5h", "5h Window")
        add_hud_cb(r_cpro, "claude-pro-7d", "Weekly (7d)")

        # 3. ChatGPT Card
        gpt_cfg = pCfg.get("chatgpt_subscription", {})
        f_gpt = make_card()
        var_chatgpt = tk.BooleanVar(value=gpt_cfg.get("enabled", True))
        add_card_header(f_gpt, "ChatGPT", var_chatgpt, "chatgpt_subscription", title_col="#8AE39A")
        wrap_gpt, ent_chatgpt_token = make_dark_entry(f_gpt, gpt_cfg.get("token", ""))
        wrap_gpt.pack(fill="x", pady=(6, 3))
        tk.Label(f_gpt, text="Access / Session token (3h window & weekly o1 quota)", font=("Sans", 7), fg="#8C8C96", bg="#1E1E22").pack(anchor="w")
        tk.Label(f_gpt, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#8AE39A", bg="#1E1E22").pack(anchor="w", pady=(5, 3))
        r_gpt = tk.Frame(f_gpt, bg="#1E1E22")
        r_gpt.pack(anchor="w")
        add_hud_cb(r_gpt, "chatgpt-4o-3h", "GPT-4o (3h)")
        add_hud_cb(r_gpt, "chatgpt-o1-weekly", "o1 Weekly")

        # 4. Cursor Card
        cur_cfg = pCfg.get("cursor", {})
        f_cur = make_card()
        var_cursor = tk.BooleanVar(value=cur_cfg.get("enabled", True))
        add_card_header(f_cur, "Cursor", var_cursor, "cursor", title_col="#C084FC")
        wrap_cur, ent_cursor_token = make_dark_entry(f_cur, cur_cfg.get("token", ""))
        wrap_cur.pack(fill="x", pady=(6, 3))
        tk.Label(f_cur, text="Cursor session token (optional if signed in to Cursor)", font=("Sans", 7), fg="#8C8C96", bg="#1E1E22").pack(anchor="w")
        tk.Label(f_cur, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#C084FC", bg="#1E1E22").pack(anchor="w", pady=(5, 3))
        r_cur = tk.Frame(f_cur, bg="#1E1E22")
        r_cur.pack(anchor="w")
        add_hud_cb(r_cur, "cursor-fast-requests", "Fast Requests")
        add_hud_cb(r_cur, "cursor-monthly-cycle", "Monthly Cycle")

        # 5. Copilot Card
        cop_cfg = pCfg.get("github_copilot", {})
        f_cop = make_card()
        var_copilot = tk.BooleanVar(value=cop_cfg.get("enabled", True))
        add_card_header(f_cop, "Copilot", var_copilot, "github_copilot", title_col="#FF5265")
        wrap_cop, ent_copilot_token = make_dark_entry(f_cop, cop_cfg.get("token", ""))
        wrap_cop.pack(fill="x", pady=(6, 3))
        tk.Label(f_cop, text="GitHub Personal Access Token for Copilot (optional)", font=("Sans", 7), fg="#8C8C96", bg="#1E1E22").pack(anchor="w")
        tk.Label(f_cop, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#FF5265", bg="#1E1E22").pack(anchor="w", pady=(5, 3))
        r_cop = tk.Frame(f_cop, bg="#1E1E22")
        r_cop.pack(anchor="w")
        add_hud_cb(r_cop, "copilot-chat-limit", "Chat Limits")
        add_hud_cb(r_cop, "copilot-completions-rate", "Completions Rate")

        gem_cfg = pCfg.get("gemini", {})
        oa_cfg = pCfg.get("openai", {})
        ant_cfg = pCfg.get("anthropic", {})

        api_ok_state = {
            "gemini": bool(gem_cfg.get("api_key_ok") and gem_cfg.get("api_key")),
            "openai": bool(oa_cfg.get("api_key_ok") and oa_cfg.get("api_key")),
            "anthropic": bool(ant_cfg.get("api_key_ok") and ant_cfg.get("api_key")),
        }
        tested_value = {
            "gemini": gem_cfg.get("api_key", "").strip() if api_ok_state["gemini"] else "",
            "openai": oa_cfg.get("api_key", "").strip() if api_ok_state["openai"] else "",
            "anthropic": ant_cfg.get("api_key", "").strip() if api_ok_state["anthropic"] else "",
        }
        api_controls = {}

        def attach_api_test_controls(row_parent, card_parent, prov_key, var_chk, ent_widget):
            status_lbl = tk.Label(
                card_parent,
                text="✓ OK — Valid API Key" if api_ok_state[prov_key] else "",
                font=("Sans", 8, "bold"),
                fg="#00E699",
                bg="#1E1E22",
                anchor="w"
            )
            btn_test = make_flat_button(
                row_parent,
                text="✓ OK" if api_ok_state[prov_key] else "Test",
                fg="#00E699" if api_ok_state[prov_key] else "#E5E7EB",
                bg="#103A2A" if api_ok_state[prov_key] else "#282832",
                hover_bg="#164D38" if api_ok_state[prov_key] else "#353544",
                font=("Sans", 8, "bold"),
                padx=12,
                pady=4,
            )

            def on_key_release(_evt=None):
                cur = ent_widget.get().strip()
                if cur != tested_value[prov_key]:
                    api_ok_state[prov_key] = False
                    status_lbl.config(text="", fg="#888888")
                    btn_test.config(text="Test", fg="#E5E7EB", bg="#282832")

            ent_widget.bind("<KeyRelease>", on_key_release)

            def run_single_test():
                key = ent_widget.get().strip()
                if not key:
                    status_lbl.config(text="⚠️ Enter an API key first", fg="#F5A623")
                    return
                btn_test.config(state="disabled", text="Loading...")
                status_lbl.config(text="Testing API key...", fg="#94A3B8")

                def worker():
                    res = test_api_key_sync(prov_key, key)
                    def finish():
                        if not (self.settings_dlg and self.settings_dlg.winfo_exists()):
                            return
                        btn_test.config(state="normal")
                        if res.get("ok"):
                            api_ok_state[prov_key] = True
                            tested_value[prov_key] = key
                            var_chk.set(True)
                            btn_test.config(text="✓ OK", fg="#00E699", bg="#103A2A")
                            status_lbl.config(text="✓ OK — Valid API Key", fg="#00E699")
                        else:
                            api_ok_state[prov_key] = False
                            tested_value[prov_key] = ""
                            btn_test.config(text="Test", fg="#E5E7EB", bg="#282832")
                            status_lbl.config(text="✕ Invalid API Key", fg="#FF4D4F")
                    dlg.after(0, finish)

                threading.Thread(target=worker, daemon=True).start()

            btn_test.config(command=run_single_test)
            api_controls[prov_key] = {
                "var": var_chk,
                "ent": ent_widget,
                "lbl": status_lbl,
                "btn": btn_test,
            }
            return btn_test, status_lbl

        # 6. Gemini Card
        var_gem = tk.BooleanVar(value=gem_cfg.get("enabled", False))
        f_gem = make_card()
        add_card_header(f_gem, "Google Gemini API (AI Studio)", var_gem, "gemini", title_col="#67E8F9")
        gem_row = tk.Frame(f_gem, bg="#1E1E22")
        gem_row.pack(fill="x", pady=(6, 2))
        wrap_gem, ent_gem = make_dark_entry(gem_row, gem_cfg.get("api_key", ""))
        wrap_gem.pack(side="left", fill="x", expand=True)
        gem_btn, gem_status = attach_api_test_controls(gem_row, f_gem, "gemini", var_gem, ent_gem)
        gem_btn.pack(side="right", padx=(6, 0))
        gem_status.pack(anchor="w", pady=(2, 2))
        link_gem = tk.Label(f_gem, text="Get a free key at Google AI Studio (aistudio.google.com) ↗", font=("Sans", 7), fg="#38BDF8", bg="#1E1E22", cursor="hand2")
        link_gem.pack(anchor="w")
        link_gem.bind("<Button-1>", lambda _e: webbrowser.open("https://aistudio.google.com/app/apikey"))
        tk.Label(f_gem, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#67E8F9", bg="#1E1E22").pack(anchor="w", pady=(5, 3))
        r_gem = tk.Frame(f_gem, bg="#1E1E22")
        r_gem.pack(anchor="w")
        add_hud_cb(r_gem, "gemini-flash-rpm", "Flash RPM")
        add_hud_cb(r_gem, "gemini-pro-rpm", "Pro RPM")
        add_hud_cb(r_gem, "gemini-key-status", "Key Status")

        # 7. OpenAI Card
        var_oa = tk.BooleanVar(value=oa_cfg.get("enabled", False))
        f_oa = make_card()
        add_card_header(f_oa, "OpenAI API (sk-...)", var_oa, "openai")
        oa_row = tk.Frame(f_oa, bg="#1E1E22")
        oa_row.pack(fill="x", pady=(6, 2))
        wrap_oa, ent_oa = make_dark_entry(oa_row, oa_cfg.get("api_key", ""))
        wrap_oa.pack(side="left", fill="x", expand=True)
        oa_btn, oa_status = attach_api_test_controls(oa_row, f_oa, "openai", var_oa, ent_oa)
        oa_btn.pack(side="right", padx=(6, 0))
        oa_status.pack(anchor="w", pady=(2, 2))
        link_oa = tk.Label(f_oa, text="Get an OpenAI API Key (platform.openai.com/api-keys) ↗", font=("Sans", 7), fg="#38BDF8", bg="#1E1E22", cursor="hand2")
        link_oa.pack(anchor="w")
        link_oa.bind("<Button-1>", lambda _e: webbrowser.open("https://platform.openai.com/api-keys"))

        # 8. Anthropic Claude API Card
        var_ant = tk.BooleanVar(value=ant_cfg.get("enabled", False))
        f_ant = make_card()
        add_card_header(f_ant, "Anthropic Claude API (sk-ant-...)", var_ant, "anthropic")
        ant_row = tk.Frame(f_ant, bg="#1E1E22")
        ant_row.pack(fill="x", pady=(6, 2))
        wrap_ant, ent_ant = make_dark_entry(ant_row, ant_cfg.get("api_key", ""))
        wrap_ant.pack(side="left", fill="x", expand=True)
        ant_btn, ant_status = attach_api_test_controls(ant_row, f_ant, "anthropic", var_ant, ent_ant)
        ant_btn.pack(side="right", padx=(6, 0))
        ant_status.pack(anchor="w", pady=(2, 2))
        link_ant = tk.Label(f_ant, text="Get an Anthropic API Key (console.anthropic.com) ↗", font=("Sans", 7), fg="#38BDF8", bg="#1E1E22", cursor="hand2")
        link_ant.pack(anchor="w")
        link_ant.bind("<Button-1>", lambda _e: webbrowser.open("https://console.anthropic.com/settings/keys"))

        # Save Action (auto-tests new/unverified API keys and marks OK)
        def write_and_close():
            hidden_list = []
            for gid, v in hud_vars.items():
                if not v.get():
                    hidden_list.append(gid)

            new_cfg = dict(cfg)
            new_cfg["providers"] = {
                "antigravity": {"enabled": var_anti.get()},
                "claude_pro": {"enabled": var_claude_pro.get(), "token": ent_claude_token.get().strip()},
                "chatgpt_subscription": {"enabled": var_chatgpt.get(), "token": ent_chatgpt_token.get().strip()},
                "cursor": {"enabled": var_cursor.get(), "token": ent_cursor_token.get().strip()},
                "github_copilot": {"enabled": var_copilot.get(), "token": ent_copilot_token.get().strip()},
                "gemini": {
                    "enabled": var_gem.get() or bool(ent_gem.get().strip()),
                    "api_key": ent_gem.get().strip(),
                    "api_key_ok": bool(api_ok_state["gemini"] and ent_gem.get().strip())
                },
                "openai": {
                    "enabled": var_oa.get() or bool(ent_oa.get().strip()),
                    "api_key": ent_oa.get().strip(),
                    "api_key_ok": bool(api_ok_state["openai"] and ent_oa.get().strip())
                },
                "anthropic": {
                    "enabled": var_ant.get() or bool(ent_ant.get().strip()),
                    "api_key": ent_ant.get().strip(),
                    "api_key_ok": bool(api_ok_state["anthropic"] and ent_ant.get().strip())
                }
            }
            new_cfg["section_colors"] = dict(sec_colors_state)
            new_cfg["refresh_interval_seconds"] = 30
            new_cfg["hidden_hud_gauges"] = hidden_list
            new_cfg["hud_auto_hide"] = bool(var_hud_auto_hide.get())
            new_cfg["hud_show_on_activity"] = bool(var_hud_show_on_activity.get())
            save_config(new_cfg)
            close_dlg()
            self.setup_ui()
            self.refresh(True)

        def do_save():
            pending = []
            for pk, ctrl in api_controls.items():
                k = ctrl["ent"].get().strip()
                if k and (not api_ok_state[pk] or k != tested_value[pk]):
                    pending.append((pk, k))

            if not pending:
                write_and_close()
                return

            btn_save.config(state="disabled", text="Testing keys...")
            for pk, _ in pending:
                api_controls[pk]["lbl"].config(text="Testing key...", fg="#94A3B8")

            def verify_worker():
                results = {}
                for pk, k in pending:
                    results[pk] = test_api_key_sync(pk, k)

                def apply_results():
                    if not (self.settings_dlg and self.settings_dlg.winfo_exists()):
                        return
                    any_ok = False
                    for pk, k in pending:
                        res = results.get(pk, {})
                        ctrl = api_controls[pk]
                        if res.get("ok"):
                            any_ok = True
                            api_ok_state[pk] = True
                            tested_value[pk] = k
                            ctrl["var"].set(True)
                            ctrl["btn"].config(text="✓ OK", fg="#00E699", bg="#103A2A")
                            ctrl["lbl"].config(text="✓ OK — Valid API Key", fg="#00E699")
                        else:
                            api_ok_state[pk] = False
                            tested_value[pk] = ""
                            ctrl["btn"].config(text="Test", fg="#E5E7EB", bg="#282832")
                            ctrl["lbl"].config(text="✕ Invalid API Key", fg="#FF4D4F")
                    btn_save.config(state="normal", text="✓ OK" if any_ok else "Save & Refresh")
                    dlg.after(500 if any_ok else 700, write_and_close)

                dlg.after(0, apply_results)

            threading.Thread(target=verify_worker, daemon=True).start()

        btn_save = make_flat_button(f_btns, "Save & Refresh", fg="#121214", bg="#00E699", hover_bg="#2BFFB5",
                                    font=("Sans", 9, "bold"), padx=16, pady=7, command=do_save)
        btn_save.pack(side="left")

        btn_cancel = make_flat_button(f_btns, "Cancel", fg="#E5E7EB", bg="#282830", hover_bg="#343440",
                                      font=("Sans", 9, "bold"), padx=14, pady=7, command=close_dlg)
        btn_cancel.pack(side="right")

    def _hide_tooltip(self, _evt=None):
        self._tooltip_text = None
        if self._tooltip_win is not None:
            try:
                if self._tooltip_win.winfo_exists():
                    self._tooltip_win.destroy()
            except Exception:
                pass
            self._tooltip_win = None

    def _show_tooltip(self, x_root, y_root, text):
        if not text:
            self._hide_tooltip()
            return
        if self._tooltip_win is not None and self._tooltip_win.winfo_exists() and self._tooltip_text == text:
            try:
                self._tooltip_win.geometry(f"+{int(x_root) + 12}+{int(y_root) + 12}")
            except Exception:
                pass
            return
        self._hide_tooltip()
        self._tooltip_text = text
        try:
            tw = tk.Toplevel(self.root)
            tw.wm_overrideredirect(True)
            tw.attributes("-topmost", True)
            tw.configure(bg="#34343B")
            lbl = tk.Label(
                tw, text=text, justify="left", anchor="w",
                bg="#1E1E22", fg="#E5E7EB", font=("Sans", 8),
                padx=8, pady=6
            )
            lbl.pack(padx=1, pady=1)
            tw.geometry(f"+{int(x_root) + 12}+{int(y_root) + 12}")
            self._tooltip_win = tw
        except Exception:
            self._tooltip_win = None

    def _draw_glyph_on_canvas(self, canvas, cx, cy, r, status, accent_color):
        if status == "working":
            track_col = blend_hex(accent_color, "#181818", 0.28)
            canvas.create_oval(cx - r, cy - r, cx + r, cy + r, outline=track_col, width=1.4)
            arc_id = canvas.create_arc(
                cx - r, cy - r, cx + r, cy + r,
                start=0, extent=135, style="arc", outline=accent_color, width=1.7
            )
            self._anim_targets.append(("arc", canvas, arc_id, []))
            return []
        if status == "waiting":
            ring_id = canvas.create_oval(cx - r * 1.1, cy - r * 1.1, cx + r * 1.1, cy + r * 1.1, outline="#F5A623", width=1.2)
            dot_r = max(1.8, r * 0.62)
            canvas.create_oval(cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r, fill="#F5A623", outline="")
            self._anim_targets.append(("pulse", canvas, ring_id, []))
            return [ring_id]
        idle_r = max(1.8, r * 0.68)
        canvas.create_oval(cx - idle_r, cy - idle_r, cx + idle_r, cy + idle_r, outline="#7A7A86", width=1.2)
        return []

    def _start_activity_animation_if_needed(self):
        if not self._anim_targets or self._anim_job is not None:
            return
        self._anim_job = self.root.after(90, self._tick_activity_animation)

    def _tick_activity_animation(self):
        self._anim_job = None
        if not self._anim_targets:
            return
        self._anim_phase = (self._anim_phase + 1) % 36
        pulse_t = 0.5 + 0.5 * math.sin((self._anim_phase / 18.0) * math.pi)
        amber_pulse = blend_hex("#F5A623", "#181818", 0.45 + 0.55 * pulse_t)
        alive = []
        for kind, cv, item_id, extra_ids in self._anim_targets:
            try:
                if not cv.winfo_exists():
                    continue
                if kind == "arc":
                    cv.itemconfigure(item_id, start=(self._anim_phase * 25) % 360)
                elif kind == "pulse":
                    cv.itemconfigure(item_id, outline=amber_pulse)
                    for bid in extra_ids:
                        try:
                            cv.itemconfigure(bid, outline=amber_pulse)
                        except Exception:
                            try:
                                cv.itemconfigure(bid, fill=amber_pulse)
                            except Exception:
                                pass
                alive.append((kind, cv, item_id, extra_ids))
            except Exception:
                pass
        self._anim_targets = alive
        if self._anim_targets:
            self._anim_job = self.root.after(90, self._tick_activity_animation)

    def setup_ui(self):
        if self._anim_job is not None:
            try:
                self.root.after_cancel(self._anim_job)
            except Exception:
                pass
            self._anim_job = None
        self._anim_targets = []
        self._hide_tooltip()
        self._active_scroll_canvas = None
        if not getattr(self, "_wheel_bound", False):
            self._wheel_bound = True
            def _dispatch_wheel(event):
                c = self._active_scroll_canvas
                if c is None:
                    return
                try:
                    if not c.winfo_exists():
                        return
                    if self.mode == "hud" and self.orientation == "horizontal":
                        if getattr(event, "num", None) == 4:
                            c.xview_scroll(-1, "units")
                        elif getattr(event, "num", None) == 5:
                            c.xview_scroll(1, "units")
                        elif getattr(event, "delta", 0):
                            c.xview_scroll(int(-1 * (event.delta / 120)), "units")
                    else:
                        if getattr(event, "num", None) == 4:
                            c.yview_scroll(-1, "units")
                        elif getattr(event, "num", None) == 5:
                            c.yview_scroll(1, "units")
                        elif getattr(event, "delta", 0):
                            c.yview_scroll(int(-1 * (event.delta / 120)), "units")
                except Exception:
                    pass
            for ev in ("<MouseWheel>", "<Button-4>", "<Button-5>"):
                self.root.bind(ev, _dispatch_wheel, add="+")

        for widget in self.root.winfo_children():
            if self.settings_dlg and widget == self.settings_dlg:
                continue
            if self.promo_window and widget == self.promo_window:
                continue
            widget.destroy()

        self.setup_hud_ui() if self.mode != "full" else self.setup_full_ui()
        self._apply_hud_auto_hide_policy()
        self._start_activity_animation_if_needed()
        self.check_and_schedule_promo()

    def _any_agent_active(self) -> bool:
        quota = self.quota if isinstance(self.quota, dict) else {}
        act = quota.get("activity") if isinstance(quota.get("activity"), dict) else {}
        if (act.get("working_count") or 0) > 0 or (act.get("waiting_count") or 0) > 0:
            return True
        for g in quota.get("groups", []) or []:
            g_act = g.get("activity") if isinstance(g, dict) else None
            if isinstance(g_act, dict) and g_act.get("state") in ("working", "waiting"):
                return True
        return False

    def _schedule_hud_auto_hide_check(self, delay_ms: int):
        if self._hud_hide_job is not None:
            try:
                self.root.after_cancel(self._hud_hide_job)
            except Exception:
                pass
            self._hud_hide_job = None
        try:
            self._hud_hide_job = self.root.after(max(100, int(delay_ms)), self._apply_hud_auto_hide_policy)
        except Exception:
            pass

    def _on_hud_enter(self, _e=None):
        if self.mode == "full":
            return
        self._is_hovering_hud = True
        self._hud_hover_reveal_until = 0.0
        if self._hud_hide_job is not None:
            try:
                self.root.after_cancel(self._hud_hide_job)
            except Exception:
                pass
            self._hud_hide_job = None

    def _on_hud_leave(self, event=None):
        if self.mode == "full":
            return
        # Only treat as leaving the HUD when cursor exits root bounds
        try:
            rx = self.root.winfo_rootx()
            ry = self.root.winfo_rooty()
            rw = self.root.winfo_width()
            rh = self.root.winfo_height()
            px, py = self.root.winfo_pointerxy()
            if rx <= px <= (rx + rw) and ry <= py <= (ry + rh):
                return
        except Exception:
            pass
        self._is_hovering_hud = False
        cfg = load_config()
        if bool(cfg.get("hud_auto_hide", False)):
            self._hud_manual_override = False
            self._hud_hover_reveal_until = 0.0
            if self._hud_idle_since is None:
                self._hud_idle_since = time.time() - 3.0
            self._schedule_hud_auto_hide_check(1500)

    def _hide_hud_peek_handle(self):
        if self._hud_peek_win is not None:
            try:
                if self._hud_peek_win.winfo_exists():
                    self._hud_peek_win.withdraw()
            except Exception:
                pass

    def _show_hud_peek_handle(self):
        if self.mode == "full":
            self._hide_hud_peek_handle()
            return
        try:
            sw = self.root.winfo_screenwidth()
            sh = self.root.winfo_screenheight()
            rx = self.root.winfo_x()
            ry = self.root.winfo_y()
            rw = max(1, self.root.winfo_width())
            rh = max(1, self.root.winfo_height())
            mid_x = rx + rw / 2.0
            mid_y = ry + rh / 2.0

            if self.orientation == "vertical":
                pw, ph = 10, 76
                on_right = mid_x >= (sw / 2.0)
                px = (sw - pw) if on_right else 0
                py = int(min(max(mid_y - ph / 2.0, 24), sh - ph - 24))
            else:
                pw, ph = 76, 10
                on_top = mid_y < (sh / 2.0)
                py = 0 if on_top else (sh - ph)
                px = int(min(max(mid_x - pw / 2.0, 24), sw - pw - 24))

            if self._hud_peek_win is None or not self._hud_peek_win.winfo_exists():
                w = tk.Toplevel(self.root)
                w.overrideredirect(True)
                try:
                    w.attributes("-topmost", True)
                except Exception:
                    pass
                w.configure(bg="#2A2A30")
                pill = tk.Frame(w, bg="#B4B4BE")
                pill.place(relx=0.5, rely=0.5, anchor="center", relwidth=0.45 if self.orientation == "vertical" else 0.72, relheight=0.72 if self.orientation == "vertical" else 0.45)
                for target in (w, pill):
                    target.bind("<Enter>", lambda _e: self._on_hud_peek_triggered())
                    target.bind("<Button-1>", lambda _e: self._on_hud_peek_triggered())
                self._hud_peek_win = w

            self._hud_peek_win.geometry(f"{pw}x{ph}+{px}+{py}")
            self._hud_peek_win.deiconify()
            self._hud_peek_win.lift()
        except Exception:
            pass

    def _on_hud_peek_triggered(self):
        if self.mode == "full":
            return
        self._hud_hover_reveal_until = time.time() + 2.5
        self._is_hovering_hud = False
        self._hide_hud_peek_handle()
        self._show_hud_animated()
        self._schedule_hud_auto_hide_check(2600)

    def _show_hud_animated(self):
        self._is_hud_fading = False
        try:
            self.root.attributes("-alpha", 1.0)
        except Exception:
            pass
        try:
            self.root.deiconify()
            self.root.lift()
        except Exception:
            pass

    def _hide_hud_animated(self):
        if self._is_hud_fading:
            return
        self._is_hud_fading = True
        steps = [0.85, 0.65, 0.42, 0.20, 0.0]

        def step_fade(idx=0):
            if not self._is_hud_fading:
                return
            if idx < len(steps):
                try:
                    self.root.attributes("-alpha", steps[idx])
                    self.root.after(35, lambda: step_fade(idx + 1))
                    return
                except Exception:
                    pass
            self._is_hud_fading = False
            try:
                self.root.withdraw()
                self.root.attributes("-alpha", 1.0)
            except Exception:
                pass
            if self.mode != "full":
                self._show_hud_peek_handle()

        step_fade(0)

    def _apply_hud_auto_hide_policy(self):
        if self.mode == "full":
            self._hud_idle_since = None
            self._hud_manual_override = False
            self._hide_hud_peek_handle()
            self._show_hud_animated()
            return

        cfg = load_config()
        auto_hide = bool(cfg.get("hud_auto_hide", False))
        if not auto_hide:
            self._hud_idle_since = None
            self._hud_manual_override = False
            self._hide_hud_peek_handle()
            self._show_hud_animated()
            return

        show_on_activity = bool(cfg.get("hud_show_on_activity", True))
        if show_on_activity and self._any_agent_active():
            self._hud_idle_since = None
            self._hud_manual_override = False
            self._hide_hud_peek_handle()
            self._show_hud_animated()
            return

        if self._is_hovering_hud or time.time() < self._hud_hover_reveal_until:
            self._hide_hud_peek_handle()
            self._show_hud_animated()
            return

        if self._hud_manual_override:
            self._hide_hud_peek_handle()
            self._show_hud_animated()
            return

        now = time.time()
        if self._hud_idle_since is None:
            self._hud_idle_since = now
            self._schedule_hud_auto_hide_check(4100)
            return

        elapsed = now - self._hud_idle_since
        if elapsed >= 4.0:
            self._hide_hud_animated()
        else:
            self._schedule_hud_auto_hide_check(int((4.0 - elapsed + 0.1) * 1000))

    def setup_full_ui(self):
        self._apply_window_chrome(borderless=False, topmost=False)
        self.root.resizable(False, False)
        self.root.configure(bg="#181818")

        quota = self.quota or {}
        groups = quota.get("groups", [])
        app_ver = get_app_version(quota)
        self.root.title(f"AI Gauge v{app_ver} - Universal AI Quota Cockpit")

        update_info = quota.get("update", {})
        announcement = quota.get("announcement")
        ann_type = (announcement.get("type") or "").lower() if isinstance(announcement, dict) else ""
        ann_title_low = (announcement.get("title") or "").strip().lower() if isinstance(announcement, dict) else ""
        show_inline_ann = (
            isinstance(announcement, dict)
            and ann_type != "publicidade"
            and bool(announcement.get("message"))
            and ann_title_low != "help ai gauge developers team"
        )
        tier_name = (quota.get("tier") or "free").lower()
        show_free_banner = tier_name not in ("pro", "enterprise")

        self.root.update_idletasks()
        sw = max(640, self.root.winfo_screenwidth())
        sh = max(480, self.root.winfo_screenheight())
        w = 468
        h = min(650, sh - 64)
        wx = max(0, (sw - w) // 2)
        wy = max(0, (sh - h) // 2)
        if self._wm_overrideredirect is not None and not getattr(self, "_full_positioned", False):
            self.root.geometry(f"{w}x{h}+{wx}+{wy}")
            self._full_positioned = True
        else:
            self.root.geometry(f"{w}x{h}")

        # 1. Fixed Header
        header_box = tk.Frame(self.root, bg="#181818", padx=18, pady=12)
        header_box.pack(fill="x", side="top")

        title_row = tk.Frame(header_box, bg="#181818")
        title_row.pack(fill="x")
        tk.Label(title_row, text="⚡ AI Gauge", font=("Sans", 13, "bold"), fg="#FFFFFF", bg="#181818").pack(side="left")
        tk.Label(title_row, text=f"v{app_ver}", font=("Sans", 9, "bold"), fg="#8C8C96", bg="#181818").pack(side="left", padx=6, pady=(2, 0))

        act_obj = quota.get("activity") if isinstance(quota.get("activity"), dict) else {}
        w_cnt = int(act_obj.get("working_count") or 0)
        wait_cnt = int(act_obj.get("waiting_count") or 0)
        sum_parts = []
        if w_cnt > 0:
            sum_parts.append(f"{w_cnt} working")
        if wait_cnt > 0:
            sum_parts.append(f"{wait_cnt} waiting")
        sum_txt = " · ".join(sum_parts) if sum_parts else "All idle"
        sum_col = "#F5A623" if wait_cnt > 0 else "#8C8C96"
        tk.Label(title_row, text=sum_txt, font=("Sans", 8, "bold"), fg=sum_col, bg="#181818").pack(side="right", pady=(2, 0))

        acc_text = f"{quota.get('account', 'Multi-Provider')}  •  Plan {quota.get('plan', 'Universal')}"
        tk.Label(header_box, text=acc_text, font=("Sans", 10), fg="#D9D9E0", bg="#181818", anchor="w").pack(fill="x", pady=(3, 0))

        poll_secs = get_effective_poll_seconds(quota)
        poll_lbl = "5 min (idle)" if poll_secs >= 300 else f"{poll_secs}s (active)"
        time_status = "(Live)" if not quota.get("from_cache") else f"(Cache {quota.get('cache_age_seconds', 0)}s)"
        time_text = f"Updated at {quota.get('updated_at', 'now')} {time_status} · Polling {poll_lbl}"
        tk.Label(header_box, text=time_text, font=("Sans", 8), fg="#8C8C96", bg="#181818", anchor="w").pack(fill="x", pady=(1, 8))
        tk.Frame(header_box, bg="#28282E", height=1).pack(fill="x")

        # 2. Fixed Equal-Width 4-Button Footer (packed before center scroll area)
        footer = tk.Frame(self.root, bg="#181818", padx=18, pady=12)
        footer.pack(fill="x", side="bottom")

        btn_row = tk.Frame(footer, bg="#181818")
        btn_row.pack(fill="x")
        for col_idx in range(4):
            btn_row.grid_columnconfigure(col_idx, weight=1, uniform="fbtn")

        self.refresh_btn = make_flat_button(btn_row, "↻ Refresh", fg="#181818", bg="#EEEEF0", hover_bg="#FFFFFF",
                                            font=("Sans", 9, "bold"), padx=4, pady=6, command=lambda: self.refresh(True))
        self.refresh_btn.grid(row=0, column=0, sticky="ew", padx=(0, 6))

        hud_btn = make_flat_button(btn_row, "⤢ HUD Bar", fg="#181818", bg="#EEEEF0", hover_bg="#FFFFFF",
                                   font=("Sans", 9, "bold"), padx=4, pady=6, command=self.toggle_mode)
        hud_btn.grid(row=0, column=1, sticky="ew", padx=(0, 6))

        cfg_btn = make_flat_button(btn_row, "⚙ Settings", fg="#181818", bg="#EEEEF0", hover_bg="#FFFFFF",
                                   font=("Sans", 9, "bold"), padx=4, pady=6, command=self.open_settings)
        cfg_btn.grid(row=0, column=2, sticky="ew", padx=(0, 6))

        close_btn = make_flat_button(btn_row, "✕ Close", fg="#181818", bg="#EEEEF0", hover_bg="#FFFFFF",
                                     font=("Sans", 9, "bold"), padx=4, pady=6, command=self.root.destroy)
        close_btn.grid(row=0, column=3, sticky="ew")

        mid = get_machine_id()
        donate_url = f"https://ai-gauge.vh2c.com.br/donate?mid={mid}" if mid else "https://ai-gauge.vh2c.com.br/donate"
        brand_lbl = tk.Label(footer, text=f"Developed by vh2c.com.br", font=("Sans", 8, "bold"),
                             fg="#8C8C96", bg="#181818", cursor="hand2")
        brand_lbl.pack(pady=(8, 0))
        brand_lbl.bind("<Button-1>", lambda _e: webbrowser.open(donate_url))

        # 3. Scrollable Center Content Area
        body_wrap = tk.Frame(self.root, bg="#181818")
        body_wrap.pack(fill="both", expand=True, padx=14)

        body_canvas = tk.Canvas(body_wrap, bg="#181818", bd=0, highlightthickness=0)
        body_scroll = tk.Scrollbar(body_wrap, orient="vertical", command=body_canvas.yview,
                                   bg="#202026", troughcolor="#141418", bd=0, highlightthickness=0, width=8)
        main_frame = tk.Frame(body_canvas, bg="#181818", padx=4, pady=4)
        body_canvas.configure(yscrollcommand=body_scroll.set)
        win_id = body_canvas.create_window((0, 0), window=main_frame, anchor="nw")

        def _sync_scroll(_evt=None):
            try:
                body_canvas.configure(scrollregion=body_canvas.bbox("all"))
                cw = body_canvas.winfo_width()
                if cw > 40:
                    body_canvas.itemconfigure(win_id, width=cw)
            except Exception:
                pass

        main_frame.bind("<Configure>", _sync_scroll)
        body_canvas.bind("<Configure>", _sync_scroll)
        body_canvas.pack(side="left", fill="both", expand=True)
        body_scroll.pack(side="right", fill="y")
        self._active_scroll_canvas = body_canvas

        # Update Available Banner (emerald compact strip)
        if update_info.get("update_available") and ann_type != "versao":
            up_box = tk.Frame(main_frame, bg="#062A1E", padx=12, pady=8, highlightbackground="#10B981", highlightthickness=1)
            up_box.pack(fill="x", pady=(2, 10))
            new_v = update_info.get("latest_version", "")
            tk.Label(up_box, text=f"New release v{new_v} available", font=("Sans", 9, "bold"), fg="#34D399", bg="#062A1E").pack(side="left")
            d_url = update_info.get("download_url") or "https://github.com/vh2c/ai-gauge/releases/latest"
            make_flat_button(up_box, "Update", fg="#121214", bg="#00E699", hover_bg="#2BFFB5",
                             font=("Sans", 8, "bold"), padx=12, pady=3, command=lambda u=d_url: webbrowser.open(u)).pack(side="right")

        # Announcement Notice Banner (versao = green strip, info = amber; ads NEVER render inline)
        if show_inline_ann:
            is_versao = (ann_type == "versao")
            if is_versao:
                ann_bg, ann_border, ann_title_col, btn_fg, btn_bg, btn_hover = "#062A1E", "#10B981", "#34D399", "#121214", "#00E699", "#2BFFB5"
            else:
                ann_bg, ann_border, ann_title_col, btn_fg, btn_bg, btn_hover = "#2D2418", "#F59E0B", "#FBBF24", "#121214", "#FBBF24", "#FCD34D"

            ann_box = tk.Frame(main_frame, bg=ann_bg, padx=12, pady=9, highlightbackground=ann_border, highlightthickness=1)
            ann_box.pack(fill="x", pady=(2, 10))

            if is_versao:
                row_v = tk.Frame(ann_box, bg=ann_bg)
                row_v.pack(fill="x")
                left_v = tk.Frame(row_v, bg=ann_bg)
                left_v.pack(side="left", fill="x", expand=True)
                tk.Label(left_v, text=announcement.get("title", "New Version Available"),
                         font=("Sans", 9, "bold"), fg=ann_title_col, bg=ann_bg, anchor="w").pack(fill="x")
                tk.Label(left_v, text=announcement.get("message", ""),
                         font=("Sans", 8), fg="#D1D5DB", bg=ann_bg, anchor="w", justify="left", wraplength=260).pack(fill="x", pady=(2, 0))
                a_url = announcement.get("action_url") or update_info.get("download_url") or "https://github.com/vh2c/ai-gauge/releases/latest"
                act_label = (announcement.get("action_label") or "Download Now").strip()
                make_flat_button(row_v, act_label, fg=btn_fg, bg=btn_bg, hover_bg=btn_hover,
                                 font=("Sans", 8, "bold"), padx=12, pady=5, command=lambda u=a_url: webbrowser.open(u)).pack(side="right", padx=(8, 0))
            else:
                tk.Label(ann_box, text=announcement.get("title", "Notice"), font=("Sans", 9, "bold"), fg=ann_title_col, bg=ann_bg, anchor="w").pack(fill="x")
                tk.Label(ann_box, text=announcement.get("message", ""), font=("Sans", 8), fg="#D1D5DB", bg=ann_bg,
                         anchor="w", justify="left", wraplength=396).pack(fill="x", pady=(3, 6))
                if announcement.get("action_label") and announcement.get("action_url"):
                    a_url = announcement.get("action_url")
                    act_label = announcement.get("action_label", "")
                    btn_text = act_label if (act_label.endswith("!") or "→" in act_label) else f"{act_label} →"
                    make_flat_button(ann_box, btn_text, fg=btn_fg, bg=btn_bg, hover_bg=btn_hover,
                                     font=("Sans", 8, "bold"), padx=14, pady=4, command=lambda u=a_url: webbrowser.open(u)).pack(anchor="center", pady=(2, 2))

        # Fixed Donation Banner for FREE users
        if show_free_banner:
            mid_f = get_machine_id()
            donate_url_f = f"https://ai-gauge.vh2c.com.br/donate?mid={mid_f}" if mid_f else "https://ai-gauge.vh2c.com.br/donate"
            free_box = tk.Frame(main_frame, bg="#2D2418", padx=12, pady=9, highlightbackground="#F59E0B", highlightthickness=1)
            free_box.pack(fill="x", pady=(0, 10))
            tk.Label(free_box, text="Help AI GAUGE developers team", font=("Sans", 9, "bold"), fg="#FBBF24", bg="#2D2418", anchor="w").pack(fill="x")
            tk.Label(free_box, text="AI GAUGE is developed by independent developers. Support this initiative by making a donation of any amount.",
                     font=("Sans", 8), fg="#D1D5DB", bg="#2D2418", anchor="w", justify="left", wraplength=396).pack(fill="x", pady=(3, 6))
            make_flat_button(free_box, "MAKE A DONATION!", fg="#121214", bg="#FBBF24", hover_bg="#FCD34D",
                             font=("Sans", 8, "bold"), padx=14, pady=4, command=lambda u=donate_url_f: webbrowser.open(u)).pack(anchor="center", pady=(2, 2))

        if not groups:
            empty_frame = tk.Frame(main_frame, bg="#1E1E22", padx=18, pady=16, highlightbackground="#2C2C30", highlightthickness=1)
            empty_frame.pack(fill="x", pady=6)
            tk.Label(empty_frame, text="⚡ Welcome to AI Gauge", font=("Sans", 11, "bold"), fg="#FFFFFF", bg="#1E1E22").pack(pady=(2, 2))
            tk.Label(empty_frame, text=f"Installed Version: v{app_ver}", font=("Sans", 8, "bold"), fg="#00E699", bg="#1E1E22").pack(pady=(0, 8))
            tk.Label(empty_frame, text="No active local sessions were found (Antigravity, Claude, ChatGPT, Cursor, Copilot).\nConfigure an API key (Gemini, OpenAI, Anthropic) or session token:",
                     font=("Sans", 8), fg="#AAAAAA", bg="#1E1E22", justify="center", wraplength=380).pack(pady=(0, 12))
            make_flat_button(empty_frame, "⚙ Configure Providers and Keys", fg="#121214", bg="#00E699", hover_bg="#2BFFB5",
                             font=("Sans", 9, "bold"), padx=16, pady=6, command=self.open_settings).pack(pady=(0, 6))
            make_flat_button(empty_frame, "Get a Free Key at Google AI Studio ↗", fg="#38BDF8", bg="#141418", hover_bg="#24242E",
                             font=("Sans", 8, "bold"), padx=12, pady=4, command=lambda: webbrowser.open("https://aistudio.google.com/app/apikey")).pack()

        cfg = load_config()
        sec_colors = cfg.get("section_colors", {})
        prov_labels = {
            "antigravity": "ANTIGRAVITY",
            "claude_pro": "CLAUDE",
            "chatgpt_subscription": "CHATGPT",
            "cursor": "CURSOR",
            "github_copilot": "COPILOT",
            "gemini": "GEMINI",
            "openai": "OPENAI",
            "anthropic": "ANTHROPIC",
        }

        for g in groups:
            pk = get_provider_key(g.get("name", ""), g.get("provider", ""))
            accent_col = sec_colors.get(pk) or PASTEL_DEFAULTS.get(pk, "#8FBCFF")
            card_title = get_section_clean_title(pk, g.get("name", "AI")) if pk != "antigravity" else (g.get("name") or "Antigravity")
            badge_label = prov_labels.get(pk, pk.upper())
            act = get_provider_activity(quota, pk) or g.get("activity") or {}
            st = (act.get("status") or "idle").lower()
            card_border = "#F5A623" if st == "waiting" else "#2C2C30"

            card = tk.Frame(main_frame, bg="#1E1E22", padx=14, pady=10, highlightbackground=card_border, highlightthickness=1)
            card.pack(fill="x", pady=(0, 10))

            # Card header INSIDE card
            hdr = tk.Frame(card, bg="#1E1E22")
            hdr.pack(fill="x")
            tk.Label(hdr, text=card_title, font=("Sans", 10, "bold"), fg="#F2F2F4", bg="#1E1E22").pack(side="left")
            tk.Label(hdr, text=badge_label, font=("Sans", 7, "bold"), fg=accent_col, bg="#1E1E22").pack(side="right")
            tk.Label(hdr, text=" · ", font=("Sans", 8, "bold"), fg="#52525B", bg="#1E1E22").pack(side="right")
            st_lbl_txt = "Waiting" if st == "waiting" else ("Working" if st == "working" else "Idle")
            st_lbl_col = "#F5A623" if st == "waiting" else ("#E5E7EB" if st == "working" else "#71717A")
            tk.Label(hdr, text=st_lbl_txt, font=("Sans", 8), fg=st_lbl_col, bg="#1E1E22").pack(side="right")
            g_cv = tk.Canvas(hdr, width=12, height=12, bg="#1E1E22", bd=0, highlightthickness=0)
            g_cv.pack(side="right", padx=(0, 3))
            self._draw_glyph_on_canvas(g_cv, 6, 6, 4.0, st, accent_col)

            tk.Frame(card, bg="#28282E", height=1).pack(fill="x", pady=(7, 7))

            det_txt = (act.get("detail") or "").strip() if isinstance(act, dict) else ""
            if st in ("working", "waiting") and det_txt:
                prefix = "Paused" if st == "waiting" else "Active"
                age_val = act.get("age_seconds")
                age_sfx = f" · {age_val}s ago" if age_val is not None else ""
                sess_col = "#F5B84D" if st == "waiting" else "#A1A1AA"
                tk.Label(card, text=f"{prefix} · {det_txt}{age_sfx}", font=("Sans", 8), fg=sess_col, bg="#1E1E22", anchor="w").pack(fill="x", pady=(0, 6))

            for idx, b in enumerate(g.get("buckets", [])):
                if idx > 0:
                    tk.Frame(card, bg="#28282E", height=1).pack(fill="x", pady=7)

                row1 = tk.Frame(card, bg="#1E1E22")
                row1.pack(fill="x")

                tk.Label(row1, text=b.get("name", ""), font=("Sans", 9), fg="#FFFFFF", bg="#1E1E22").pack(side="left")

                is_outdated = (b.get("reset_in") == "Outdated")
                pct = 0 if is_outdated else b.get("remaining_pct", 100)
                val_col = "#F5A623" if is_outdated else status_color(pct, accent_col)
                val_str = "--%" if is_outdated else f"{pct}%"

                tk.Label(row1, text=val_str, font=("Monospace", 10, "bold"), fg=val_col, bg="#1E1E22", width=4, anchor="e").pack(side="right")

                rt = b.get("reset_in") or ""
                if rt:
                    if is_outdated:
                        rt_txt = "Outdated · sign in again"
                        rt_col = "#F5A623"
                    elif rt == "Now":
                        rt_txt = "Renews now"
                        rt_col = "#8C8C96"
                    elif rt == "Active":
                        rt_txt = "Active"
                        rt_col = "#8C8C96"
                    else:
                        rt_txt = f"Renews in {rt}"
                        rt_col = "#8C8C96"
                    tk.Label(row1, text=rt_txt, font=("Sans", 8), fg=rt_col, bg="#1E1E22").pack(side="right", padx=(0, 8))

                bar_canvas = tk.Canvas(card, bg="#28282D", height=6, highlightthickness=0, bd=0)
                bar_canvas.pack(fill="x", pady=(5, 1))

                def _draw_bar(event, cv=bar_canvas, p=pct, col=val_col):
                    try:
                        cw = max(10, event.width)
                        cv.delete("all")
                        fw = 0 if p <= 0 else max(4, int(cw * (min(100, p) / 100.0)))
                        if fw > 0:
                            cv.create_rectangle(0, 0, fw, 6, fill=col, outline="")
                    except Exception:
                        pass

                bar_canvas.bind("<Configure>", _draw_bar)
                bar_canvas.create_rectangle(0, 0, max(4, int(390 * (pct / 100.0))), 6, fill=val_col, outline="")

        _sync_scroll()

    def _show_hud_menu(self, widget_event=None):
        menu = tk.Menu(self.root, tearoff=0, bg="#1E1E24", fg="#FFFFFF", activebackground="#2E3242", activeforeground="#FFFFFF", bd=0)
        menu.add_command(label="Open Full Window (Ctrl+M)", command=self.toggle_mode)
        orient_lbl = "Switch to Horizontal Bar" if self.orientation == "vertical" else "Switch to Vertical Bar"
        menu.add_command(label=orient_lbl, command=self.toggle_orientation)
        menu.add_command(label="Refresh Data Now", command=lambda: self.refresh(True))
        menu.add_command(label="Settings...", command=self.open_settings)
        menu.add_separator()
        menu.add_command(label="Quit AI Gauge", command=self.root.destroy)
        try:
            rx = widget_event.x_root if widget_event else (self.root.winfo_rootx() + 50)
            ry = widget_event.y_root if widget_event else (self.root.winfo_rooty() + 26)
            menu.tk_popup(rx, ry)
        finally:
            try:
                menu.grab_release()
            except Exception:
                pass

    def setup_hud_ui(self):
        self._apply_window_chrome(borderless=True, topmost=True)
        self.root.configure(bg="#181818")

        quota = self.quota or {}
        sections = get_hud_sections(quota)
        is_vert = (self.orientation == "vertical")
        total_items = sum(len(s["items"]) for s in sections)

        self.root.update_idletasks()
        sw = max(640, self.root.winfo_screenwidth())
        sh = max(480, self.root.winfo_screenheight())

        item_h = 104
        if is_vert:
            w = 118
            top_h = 26
            bot_h = 20
            content_h = 120 if total_items == 0 else sum(22 + len(s["items"]) * item_h + 10 for s in sections) + 8
            h = min(max(170, top_h + content_h + bot_h), max(220, sh - 64))
        else:
            w_content = 250 if total_items == 0 else sum(max(106, len(s["items"]) * 96 + 14) + 10 for s in sections) + 34
            w = min(max(260, w_content), max(300, sw - 40))
            h = 134

        if self._hud_pos is not None:
            x, y = self._hud_pos
        elif is_vert:
            x = sw - w - 20
            y = (sh - h) // 2
        else:
            x = (sw - w) // 2
            y = sh - h - 40
        x = max(0, min(x, max(0, sw - w)))
        y = max(0, min(y, max(0, sh - h)))
        self._hud_pos = (x, y)
        self.root.geometry(f"{w}x{h}+{x}+{y}")

        self._drag_data = {"x": 0, "y": 0}
        def start_drag(event):
            self._drag_data["x"] = event.x_root - self.root.winfo_rootx()
            self._drag_data["y"] = event.y_root - self.root.winfo_rooty()
        def do_drag(event):
            nx = max(0, min(event.x_root - self._drag_data["x"], max(0, sw - w)))
            ny = max(0, min(event.y_root - self._drag_data["y"], max(0, sh - h)))
            self._hud_pos = (nx, ny)
            try:
                self.root.geometry(f"+{nx}+{ny}")
            except Exception:
                pass

        outer = tk.Frame(self.root, bg="#181818", highlightbackground="#2A2A2E", highlightthickness=1, bd=0)
        outer.pack(fill="both", expand=True)

        if is_vert:
            # Top Control Bar (matches macOS & Windows: ⤢  ⋯  ✕)
            top_bar = tk.Frame(outer, bg="#181818", height=24)
            top_bar.pack(fill="x", side="top", padx=4, pady=(4, 2))
            top_bar.bind("<Button-1>", start_drag)
            top_bar.bind("<B1-Motion>", do_drag)

            b_cockpit = make_flat_button(top_bar, "⤢", fg="#A6A6AE", bg="#181818", hover_bg="#26262E", font=("Sans", 10, "bold"), padx=4, pady=0, command=self.toggle_mode)
            b_cockpit.pack(side="left")
            b_menu = tk.Label(top_bar, text="⋯", font=("Sans", 11, "bold"), fg="#A6A6AE", bg="#181818", cursor="hand2", padx=4)
            b_menu.pack(side="left", expand=True)
            b_menu.bind("<Button-1>", self._show_hud_menu)
            b_menu.bind("<Enter>", lambda _e: b_menu.config(fg="#FFFFFF"))
            b_menu.bind("<Leave>", lambda _e: b_menu.config(fg="#A6A6AE"))
            b_close = make_flat_button(top_bar, "✕", fg="#A6A6AE", bg="#181818", hover_bg="#26262E", font=("Sans", 9, "bold"), padx=4, pady=0, command=self.root.destroy)
            b_close.pack(side="right")

            # Bottom Brand / Update Strip
            bot_bar = tk.Frame(outer, bg="#181818", height=18)
            bot_bar.pack(fill="x", side="bottom", pady=(2, 4))
            bot_bar.bind("<Button-1>", start_drag)
            bot_bar.bind("<B1-Motion>", do_drag)
            if quota.get("update", {}).get("update_available"):
                d_url = quota.get("update", {}).get("download_url") or "https://github.com/vh2c/ai-gauge/releases/latest"
                lbl_up = tk.Label(bot_bar, text="● NEW VERSION", font=("Sans", 7, "bold"), fg="#00E699", bg="#181818", cursor="hand2")
                lbl_up.pack()
                lbl_up.bind("<Button-1>", lambda _e, u=d_url: webbrowser.open(u))
            else:
                mid = get_machine_id()
                donate_url = f"https://ai-gauge.vh2c.com.br/donate?mid={mid}" if mid else "https://ai-gauge.vh2c.com.br/donate"
                lbl_b = tk.Label(bot_bar, text="vh2c.com.br", font=("Sans", 7), fg="#73737D", bg="#181818", cursor="hand2")
                lbl_b.pack()
                lbl_b.bind("<Button-1>", lambda _e, u=donate_url: webbrowser.open(u))

            # Scrollable Tachometer Sections Canvas
            hud_canvas = tk.Canvas(outer, bg="#181818", bd=0, highlightthickness=0)
            hud_canvas.pack(fill="both", expand=True)
            self._active_scroll_canvas = hud_canvas
            hud_canvas.bind("<Button-1>", lambda e: (self._hide_tooltip(), start_drag(e)))
            hud_canvas.bind("<B1-Motion>", do_drag)
            hud_canvas.bind("<Double-Button-1>", lambda _e: self.toggle_mode())

            section_hit_areas = []
            poll_secs = get_effective_poll_seconds(quota)

            if total_items == 0:
                self.draw_section_frame(hud_canvas, 8, 10, 100, 102, "No Quotas", "#8FBCFF")
                t_cfg = hud_canvas.create_text(58, 56, text="Click to\nConfigure", font=("Sans", 8, "bold"), fill="#8FBCFF", justify="center")
                hud_canvas.tag_bind(t_cfg, "<Button-1>", lambda _e: self.open_settings())
                hud_canvas.configure(scrollregion=(0, 0, w, 120))
            else:
                cur_y = 6
                for sec in sections:
                    sec_h = 20 + len(sec["items"]) * item_h
                    act = sec.get("activity")
                    st = (act.get("status") if isinstance(act, dict) else None) or "idle"
                    self.draw_section_frame(hud_canvas, 6, cur_y, 104, sec_h, sec["title"], sec["accent"], activity_status=st)
                    section_hit_areas.append((6, cur_y, 110, cur_y + sec_h, format_activity_tooltip(sec["title"], act, poll_secs)))
                    gy = cur_y + 16
                    for item in sec["items"]:
                        self.draw_tachometer_gauge(hud_canvas, 58, gy + 44, item)
                        gy += item_h
                    cur_y += sec_h + 10
                hud_canvas.configure(scrollregion=(0, 0, w, cur_y + 4))

            def _on_hud_v_motion(event, areas=section_hit_areas, cv=hud_canvas):
                cy = cv.canvasy(event.y)
                cx = cv.canvasx(event.x)
                for x1, y1, x2, y2, tip in areas:
                    if x1 <= cx <= x2 and y1 <= cy <= y2:
                        self._show_tooltip(event.x_root, event.y_root, tip)
                        return
                self._hide_tooltip()
            hud_canvas.bind("<Motion>", _on_hud_v_motion)
            hud_canvas.bind("<Leave>", self._hide_tooltip)
        else:
            # Horizontal Bar with right-edge control strip matching macOS Horizontal HUD
            ctrl_col = tk.Frame(outer, bg="#181818", width=26)
            ctrl_col.pack(fill="y", side="right", padx=(2, 4), pady=6)
            make_flat_button(ctrl_col, "✕", fg="#A6A6AE", bg="#181818", hover_bg="#26262E", font=("Sans", 9, "bold"), padx=4, pady=2, command=self.root.destroy).pack(side="top")
            make_flat_button(ctrl_col, "⤢", fg="#A6A6AE", bg="#181818", hover_bg="#26262E", font=("Sans", 10, "bold"), padx=4, pady=2, command=self.toggle_mode).pack(side="top", expand=True)
            b_hm = tk.Label(ctrl_col, text="⋯", font=("Sans", 11, "bold"), fg="#A6A6AE", bg="#181818", cursor="hand2")
            b_hm.pack(side="bottom")
            b_hm.bind("<Button-1>", self._show_hud_menu)

            hud_canvas = tk.Canvas(outer, bg="#181818", bd=0, highlightthickness=0)
            hud_canvas.pack(fill="both", expand=True)
            self._active_scroll_canvas = hud_canvas
            hud_canvas.bind("<Button-1>", lambda e: (self._hide_tooltip(), start_drag(e)))
            hud_canvas.bind("<B1-Motion>", do_drag)
            hud_canvas.bind("<Double-Button-1>", lambda _e: self.toggle_mode())

            section_hit_areas_h = []
            poll_secs = get_effective_poll_seconds(quota)

            if total_items == 0:
                hud_canvas.create_text(120, 56, text="No active quotas · Open Settings", font=("Sans", 9, "bold"), fill="#8FBCFF")
                hud_canvas.configure(scrollregion=(0, 0, 240, h))
            else:
                cur_x = 10
                for sec in sections:
                    n = len(sec["items"])
                    sec_w = 12 + n * 96 + 6
                    act = sec.get("activity")
                    st = (act.get("status") if isinstance(act, dict) else None) or "idle"
                    self.draw_section_frame(hud_canvas, cur_x, 8, sec_w, 114, sec["title"], sec["accent"], activity_status=st)
                    section_hit_areas_h.append((cur_x, 8, cur_x + sec_w, 122, format_activity_tooltip(sec["title"], act, poll_secs)))
                    gx = cur_x + 56
                    for item in sec["items"]:
                        self.draw_tachometer_gauge(hud_canvas, gx, 58, item)
                        gx += 96
                    cur_x += sec_w + 10
                hud_canvas.configure(scrollregion=(0, 0, cur_x + 8, h))

            def _on_hud_h_motion(event, areas=section_hit_areas_h, cv=hud_canvas):
                cy = cv.canvasy(event.y)
                cx = cv.canvasx(event.x)
                for x1, y1, x2, y2, tip in areas:
                    if x1 <= cx <= x2 and y1 <= cy <= y2:
                        self._show_tooltip(event.x_root, event.y_root, tip)
                        return
                self._hide_tooltip()
            hud_canvas.bind("<Motion>", _on_hud_h_motion)
            hud_canvas.bind("<Leave>", self._hide_tooltip)

    def draw_section_frame(self, canvas, x, y, w, h, title, accent_color, activity_status="idle"):
        r = 11
        title_str = title or "AI"
        if activity_status == "waiting":
            border_col = "#F5A623"
            title_col = "#F5A623"
        elif activity_status == "working":
            border_col = accent_color
            title_col = accent_color
        else:
            border_col = blend_hex(accent_color, "#181818", 0.42)
            title_col = blend_hex(accent_color, "#181818", 0.75)

        glyph_d = 8.0
        glyph_gap = 4.0
        content_w = glyph_d + glyph_gap + len(title_str) * 6.2
        gap_half = min((w / 2.0) - r - 1.0, max(20.0, (content_w / 2.0) + 5.0))
        cx = x + w / 2.0

        # Rounded border with clean top opening for the glyph + centered title
        border_ids = [
            canvas.create_arc(x, y, x + 2 * r, y + 2 * r, start=90, extent=90, style="arc", outline=border_col, width=1.6),
            canvas.create_arc(x + w - 2 * r, y, x + w, y + 2 * r, start=0, extent=90, style="arc", outline=border_col, width=1.6),
            canvas.create_arc(x + w - 2 * r, y + h - 2 * r, x + w, y + h, start=270, extent=90, style="arc", outline=border_col, width=1.6),
            canvas.create_arc(x, y + h - 2 * r, x + 2 * r, y + h, start=180, extent=90, style="arc", outline=border_col, width=1.6),
        ]

        if cx - gap_half > x + r:
            border_ids.append(canvas.create_line(x + r, y, cx - gap_half, y, fill=border_col, width=1.6, capstyle="round"))
        if x + w - r > cx + gap_half:
            border_ids.append(canvas.create_line(cx + gap_half, y, x + w - r, y, fill=border_col, width=1.6, capstyle="round"))
        border_ids.append(canvas.create_line(x + w, y + r, x + w, y + h - r, fill=border_col, width=1.6, capstyle="round"))
        border_ids.append(canvas.create_line(x + r, y + h, x + w - r, y + h, fill=border_col, width=1.6, capstyle="round"))
        border_ids.append(canvas.create_line(x, y + r, x, y + h - r, fill=border_col, width=1.6, capstyle="round"))

        start_x = cx - (content_w / 2.0)
        glyph_cx = start_x + (glyph_d / 2.0)
        pulse_ids = self._draw_glyph_on_canvas(canvas, glyph_cx, y, 3.6, activity_status, accent_color)
        if activity_status == "waiting" and self._anim_targets:
            last_kind, last_cv, last_item, _ = self._anim_targets[-1]
            if last_kind == "pulse":
                self._anim_targets[-1] = (last_kind, last_cv, last_item, border_ids)

        text_cx = start_x + glyph_d + glyph_gap + ((len(title_str) * 6.2) / 2.0)
        canvas.create_text(text_cx, y, text=title_str, font=("Sans", 8, "bold"), fill=title_col)

    def draw_tachometer_gauge(self, canvas, cx, cy, item):
        is_outdated = (item.get("reset_in") == "Outdated")
        pct = 0 if is_outdated else max(0, min(100, int(item.get("pct", 100))))
        col = "#F5A623" if is_outdated else status_color(pct, item.get("accent"))

        r_arc = 30.0
        start_deg = 220.0
        total_sweep = 260.0

        # Top limit label cleanly centered above arc
        canvas.create_text(cx, cy - r_arc - 9, text=item.get("title", ""), font=("Sans", 6, "bold"), fill="#A8A8B4")

        # Dark circular dial background
        r_bg = 28.0
        canvas.create_oval(cx - r_bg, cy - r_bg, cx + r_bg, cy + r_bg, fill="#141416", outline="")

        # Track arc (260 degrees from bottom-left 220° clockwise across top to bottom-right -40°)
        canvas.create_arc(
            cx - r_arc, cy - r_arc, cx + r_arc, cy + r_arc,
            start=start_deg, extent=-total_sweep, style="arc", outline="#2A2A2D", width=5
        )

        # 24 radial graduation tick marks matching macOS TachometerGaugeView
        num_ticks = 24
        for i in range(num_ticks + 1):
            frac = i / float(num_ticks)
            ang_deg = start_deg - frac * total_sweep
            rad = math.radians(ang_deg)
            is_major = (i % 6 == 0)
            r_in = r_arc - 3.5
            r_out = r_in - (4.2 if is_major else 2.5)
            x1 = cx + math.cos(rad) * r_in
            y1 = cy - math.sin(rad) * r_in
            x2 = cx + math.cos(rad) * r_out
            y2 = cy - math.sin(rad) * r_out
            canvas.create_line(x1, y1, x2, y2, fill="#8C8C94" if is_major else "#54545C", width=1.2 if is_major else 0.8)

        # Active progress arc
        sweep = (pct / 100.0) * total_sweep
        if sweep >= 1.0:
            canvas.create_arc(
                cx - r_arc, cy - r_arc, cx + r_arc, cy + r_arc,
                start=start_deg, extent=-min(259.8, sweep), style="arc", outline=col, width=5
            )

        # Tachometer needle pointer
        cur_deg = start_deg - sweep
        n_rad = math.radians(cur_deg)
        n_len = r_arc - 6.0
        tip_x = cx + math.cos(n_rad) * n_len
        tip_y = cy - math.sin(n_rad) * n_len
        base_r = 2.2
        b1_rad = n_rad + math.pi / 2.0
        b2_rad = n_rad - math.pi / 2.0
        b1x = cx + math.cos(b1_rad) * base_r
        b1y = cy - math.sin(b1_rad) * base_r
        b2x = cx + math.cos(b2_rad) * base_r
        b2y = cy - math.sin(b2_rad) * base_r
        canvas.create_polygon(b1x, b1y, tip_x, tip_y, b2x, b2y, fill="#F5F5FA", outline="")

        # Center hub pin
        hub_r = 3.5
        canvas.create_oval(cx - hub_r, cy - hub_r, cx + hub_r, cy + hub_r, fill="#26262B", outline=col, width=1.3)

        # Bottom-center percentage readout
        pct_text = "--%" if is_outdated else f"{pct}%"
        canvas.create_text(cx, cy + 16, text=pct_text, font=("Monospace", 9, "bold"), fill=col if is_outdated else "#FFFFFF")

        # Model name and reset countdown underneath
        canvas.create_text(cx, cy + 36, text=item.get("model", ""), font=("Sans", 8, "bold"), fill="#D0D5DD")
        rt = item.get("reset_in", "") or "Active"
        canvas.create_text(cx, cy + 48, text=rt, font=("Sans", 7), fill="#F5A623" if is_outdated else "#8E8E98")

def main():
    has_display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
    if "--cli" in sys.argv or not has_display:
        quota = load_quota(force=("--force" in sys.argv))
        print_cli(quota)
        return

    if not HAS_TK:
        print("⚠️  Module python3-tk (Tkinter) not found.")
        print("💡 To open the graphical interface on Ubuntu, run: sudo apt install -y python3-tk")
        print("⚡ Showing quotas in terminal mode (CLI):\n")
        quota = load_quota(force=("--force" in sys.argv))
        print_cli(quota)
        return

    print("⚡ Opening the AI Gauge graphical interface...")
    app = QuotaHubAppLinux()
    app.root.mainloop()

if __name__ == "__main__":
    main()
