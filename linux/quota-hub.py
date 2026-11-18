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

CONFIG_DIR = Path.home() / ".config" / "UniversalAIQuota"
CONFIG_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_FILE = CONFIG_DIR / "config.json"
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

def send_telemetry_heartbeat():
    def _do_send():
        try:
            url = "https://api.vh2c.com.br/v1/geminigauje"
            payload = json.dumps({
                "app": "gemini-gauge",
                "version": "1.1.1",
                "os": "Linux",
                "arch": platform.machine(),
                "machine_id": get_machine_id(),
                "timestamp": int(time.time())
            }).encode("utf-8")
            req = urllib.request.Request(
                url,
                data=payload,
                headers={
                    "Content-Type": "application/json",
                    "User-Agent": "AIGauge/1.1 (Linux; VH2C)"
                },
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=2.5) as resp:
                _ = resp.read()
        except Exception:
            pass
    threading.Thread(target=_do_send, daemon=True).start()

def load_config():
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
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

def load_quota(force=False):
    if not force and CACHE_FILE.exists():
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            ts = data.get("timestamp", 0)
            if time.time() - ts < 30:
                data["from_cache"] = True
                data["cache_age_seconds"] = int(time.time() - ts)
                return data
        except Exception:
            pass

    node_bin = find_node()
    env = dict(os.environ)
    extra_paths = ["/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    env["PATH"] = ":".join(extra_paths) + ":" + env.get("PATH", "")

    try:
        res = subprocess.run([node_bin, str(ENGINE_SCRIPT)], capture_output=True, text=True, env=env, timeout=7)
        if res.returncode == 0 and res.stdout.strip():
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
                return json.load(f)
        except Exception:
            pass
    return None

def get_gauge_items(quota):
    cfg = load_config()
    hidden_set = set(cfg.get("hidden_hud_gauges", []))
    sec_colors = cfg.get("section_colors", {})
    items = []
    for g in quota.get("groups", []):
        gname = g.get("name", "").lower()
        prov = g.get("provider", "").lower()
        if "cursor" in gname or "cursor" in prov:
            model = "Cursor"
            accent = sec_colors.get("cursor", "#C084FC")
        elif "copilot" in gname or "copilot" in prov or "github" in prov:
            model = "Copilot"
            accent = sec_colors.get("github_copilot", "#FF5265")
        elif "claude and gpt" in gname:
            model = "Claude/GPT"
            accent = sec_colors.get("antigravity", "#8FBCFF")
        elif "claude" in gname or "claude" in prov:
            model = "Claude"
            accent = sec_colors.get("claude_pro", "#D78C68")
        elif "chatgpt" in gname or "chatgpt" in prov:
            model = "ChatGPT"
            accent = sec_colors.get("chatgpt_subscription", "#8AE39A")
        elif "gemini 4" in gname or "argon" in gname:
            model = "Argon"
            accent = sec_colors.get("antigravity", "#8FBCFF")
        elif "claude" in gname or "gpt" in gname:
            model = "Claude/GPT"
            accent = sec_colors.get("antigravity", "#8FBCFF")
        elif "openai" in gname:
            model = "OpenAI"
            accent = sec_colors.get("openai", "#8AE39A")
        elif "anthropic" in gname:
            model = "Claude API"
            accent = sec_colors.get("anthropic", "#D78C68")
        elif "studio" in prov or "gemini api" in gname or "gemini" in prov:
            model = "Gemini Flash" if "flash" in gname else "Gemini Pro"
            accent = sec_colors.get("gemini", "#67E8F9")
        else:
            model = "Gemini"
            accent = sec_colors.get("gemini", "#67E8F9")

        for b in g.get("buckets", []):
            bid = b.get("id", "")
            if bid in hidden_set:
                continue
            bname = b.get("name", "").lower()
            if "5" in bname or "five" in bname or "5h" in bid:
                limit_title = "5 hours Limit"
            elif "flash" in bname or "flash" in bid:
                limit_title = "Flash RPM"
            elif "pro" in bid:
                limit_title = "Pro RPM"
            elif "key" in bid or "status" in bname:
                limit_title = "API Key"
            elif "tpm" in bname or "token" in bname:
                limit_title = "TPM Limit"
            else:
                limit_title = "Weekly Limit"

            items.append({
                "id": bid,
                "title": limit_title,
                "model": model,
                "pct": b.get("remaining_pct", 100),
                "reset_in": b.get("reset_in", ""),
                "detail": b.get("detail", ""),
                "provider": g.get("provider", ""),
                "accent": accent
            })
    return items

def status_color(pct, custom_accent=None):
    if pct > 50:
        return custom_accent if custom_accent else "#8FBCFF"
    elif pct > 20:
        return "#F5A623"
    else:
        return "#FF4D4F"

def print_cli(quota):
    send_telemetry_heartbeat()
    if not quota or quota.get("needs_setup"):
        print("\n" + "="*58)
        print(" ⚡ Universal AI Quota Monitor - Setup Required")
        print("="*58)
        print(" No active or configured AI provider.")
        print(f" Configure your keys in: {CONFIG_FILE}")
        print(" Example: add GEMINI_API_KEY or OPENAI_API_KEY.")
        print("="*58 + "\n")
        return

    print("\n" + "="*58)
    print(f" ⚡ Universal AI Quota Monitor - vh2c.com.br")
    print(f" Account: {quota.get('account', 'Multi-Provider')} • Plan {quota.get('plan', 'Universal')}")
    print(f" Updated at {quota.get('updated_at', 'now')} " + ("(Live)" if not quota.get("from_cache") else "(Cache)"))
    print("="*58)

    for g in quota.get("groups", []):
        prov = f" [{g.get('provider')}]" if g.get('provider') else ""
        print(f"\n📂 {g.get('name', 'Group').upper()}{prov}")
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

class QuotaHubAppLinux:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("AI Gauge - Universal AI Quota Cockpit")
        self.root.configure(bg="#181818")

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

        # Send Telemetry Heartbeat to VH2C API
        send_telemetry_heartbeat()

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
                    self.quota = json.load(f)
            except Exception:
                pass

        self.is_refreshing = False

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
        self.root.after(30000, self.auto_refresh)

    def auto_refresh(self):
        # Do not refresh or rebuild UI while the user is actively configuring settings
        if not (self.settings_dlg and self.settings_dlg.winfo_exists()):
            self.refresh(animated=False)
        self.schedule_auto_refresh()

    def refresh(self, animated=True):
        if self.is_refreshing:
            return
        self.is_refreshing = True
        if animated and hasattr(self, "refresh_btn"):
            self.refresh_btn.config(text="Refreshing...")
            self.root.update_idletasks()

        def do_fetch():
            new_data = load_quota(force=True)
            self.root.after(0, lambda: self.on_fetched(new_data))

        import threading
        threading.Thread(target=do_fetch, daemon=True).start()

    def on_fetched(self, data):
        self.is_refreshing = False
        if data:
            self.quota = data
            # If settings window is currently open, don't interrupt user typing
            if not (self.settings_dlg and self.settings_dlg.winfo_exists()):
                self.setup_ui()

    def toggle_mode(self):
        self.mode = "hud" if self.mode == "full" else "full"
        self.save_prefs()
        self.setup_ui()

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

        dlg = tk.Toplevel(self.root)
        self.settings_dlg = dlg
        dlg.title("Configure AI Providers - AI Gauge")
        dlg.geometry("520x600")
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

        header = tk.Label(dlg, text="⚙️ AI Providers & Gauge Selection", font=("Sans", 11, "bold"), fg="#FFFFFF", bg="#181818")
        header.pack(fill="x", pady=(14, 4), padx=16)

        sub = tk.Label(dlg, text="Enable your providers and select the gauges for your HUD side panel:", font=("Sans", 8), fg="#999999", bg="#181818")
        sub.pack(fill="x", padx=16, pady=(0, 10))

        # Bottom buttons bar (packed first with side="bottom" to guarantee visibility)
        f_btns = tk.Frame(dlg, bg="#181818", padx=16, pady=12)
        f_btns.pack(fill="x", side="bottom")

        # Canvas with scrollbar for cards
        c_frame = tk.Frame(dlg, bg="#181818")
        c_frame.pack(fill="both", expand=True, padx=12, pady=4)
        c_canvas = tk.Canvas(c_frame, bg="#181818", highlightthickness=0)
        c_scrollbar = tk.Scrollbar(c_frame, orient="vertical", command=c_canvas.yview)
        cards_box = tk.Frame(c_canvas, bg="#181818")
        cards_box.bind("<Configure>", lambda e: c_canvas.configure(scrollregion=c_canvas.bbox("all")))
        c_canvas.create_window((0, 0), window=cards_box, anchor="nw", width=480)
        c_canvas.configure(yscrollcommand=c_scrollbar.set)
        c_canvas.pack(side="left", fill="both", expand=True)
        c_scrollbar.pack(side="right", fill="y")

        def _on_mousewheel(event):
            if event.num == 4:
                c_canvas.yview_scroll(-1, "units")
            elif event.num == 5:
                c_canvas.yview_scroll(1, "units")
            elif event.delta:
                c_canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")
        c_canvas.bind_all("<MouseWheel>", _on_mousewheel)
        c_canvas.bind_all("<Button-4>", _on_mousewheel)
        c_canvas.bind_all("<Button-5>", _on_mousewheel)

        hud_vars = {}
        def add_hud_cb(parent, gid, label):
            v = tk.BooleanVar(value=(gid not in hidden_set))
            hud_vars[gid] = v
            cb = tk.Checkbutton(parent, text=label, variable=v, font=("Sans", 8), fg="#CCCCCC", bg="#1F1F1F",
                                selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#FFFFFF")
            cb.pack(side="left", padx=4)

        # 1. Antigravity Card
        f_anti = tk.Frame(cards_box, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_anti.pack(fill="x", pady=5)
        var_anti = tk.BooleanVar(value=pCfg.get("antigravity", {}).get("enabled", True))
        cb_anti = tk.Checkbutton(f_anti, text="Antigravity IDE (Live & Headless Standalone)", variable=var_anti,
                                 font=("Sans", 9, "bold"), fg="#FFFFFF", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#FFFFFF")
        cb_anti.pack(anchor="w")
        tk.Label(f_anti, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#888888", bg="#1F1F1F").pack(anchor="w", pady=(4, 2))
        r_anti1 = tk.Frame(f_anti, bg="#1F1F1F")
        r_anti1.pack(anchor="w")
        add_hud_cb(r_anti1, "gemini-weekly", "Gemini Weekly")
        add_hud_cb(r_anti1, "gemini-5h", "Gemini (5h)")
        add_hud_cb(r_anti1, "gemini-argon-wtu-weekly", "Argon")
        r_anti2 = tk.Frame(f_anti, bg="#1F1F1F")
        r_anti2.pack(anchor="w", pady=(2, 0))
        add_hud_cb(r_anti2, "3p-weekly", "Claude/GPT Weekly")
        add_hud_cb(r_anti2, "3p-5h", "Claude/GPT (5h)")

        # 2. Claude Pro Card (#D78C68)
        cpro_cfg = pCfg.get("claude_pro", {})
        f_cpro = tk.Frame(cards_box, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#D78C68", highlightthickness=1)
        f_cpro.pack(fill="x", pady=5)
        var_claude_pro = tk.BooleanVar(value=cpro_cfg.get("enabled", True))
        cb_cpro = tk.Checkbutton(f_cpro, text="Claude (Session & Limits)", variable=var_claude_pro,
                                 font=("Sans", 9, "bold"), fg="#D78C68", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#D78C68")
        cb_cpro.pack(anchor="w")
        ent_claude_token = tk.Entry(f_cpro, font=("Sans", 8), bg="#141414", fg="#FFFFFF", insertbackground="white", show="•")
        ent_claude_token.insert(0, cpro_cfg.get("token", ""))
        ent_claude_token.pack(fill="x", pady=2)
        tk.Label(f_cpro, text="💡 Optional OAuth token (auto-detected if a session exists)", font=("Sans", 7), fg="#888888", bg="#1F1F1F").pack(anchor="w")
        tk.Label(f_cpro, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#D78C68", bg="#1F1F1F").pack(anchor="w", pady=(4, 2))
        r_cpro = tk.Frame(f_cpro, bg="#1F1F1F")
        r_cpro.pack(anchor="w")
        add_hud_cb(r_cpro, "claude-pro-5h", "Janela de 5h")
        add_hud_cb(r_cpro, "claude-pro-7d", "Weekly Quota (7d)")

        # 3. ChatGPT Card
        gpt_cfg = pCfg.get("chatgpt_subscription", {})
        f_gpt = tk.Frame(cards_box, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_gpt.pack(fill="x", pady=5)
        var_chatgpt = tk.BooleanVar(value=gpt_cfg.get("enabled", True))
        cb_gpt = tk.Checkbutton(f_gpt, text="ChatGPT", variable=var_chatgpt,
                                font=("Sans", 9, "bold"), fg="#8AE39A", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#8AE39A")
        cb_gpt.pack(anchor="w")
        ent_chatgpt_token = tk.Entry(f_gpt, font=("Sans", 8), bg="#141414", fg="#FFFFFF", insertbackground="white", show="•")
        ent_chatgpt_token.insert(0, gpt_cfg.get("token", ""))
        ent_chatgpt_token.pack(fill="x", pady=2)
        tk.Label(f_gpt, text="💡 ChatGPT Access / Session Token (3h window and o1 quota)", font=("Sans", 7), fg="#888888", bg="#1F1F1F").pack(anchor="w")
        tk.Label(f_gpt, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#8AE39A", bg="#1F1F1F").pack(anchor="w", pady=(4, 2))
        r_gpt = tk.Frame(f_gpt, bg="#1F1F1F")
        r_gpt.pack(anchor="w")
        add_hud_cb(r_gpt, "chatgpt-4o-3h", "GPT-4o (3h)")
        add_hud_cb(r_gpt, "chatgpt-o1-weekly", "o1 Weekly")

        # 4. Cursor Card
        cur_cfg = pCfg.get("cursor", {})
        f_cur = tk.Frame(cards_box, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_cur.pack(fill="x", pady=5)
        var_cursor = tk.BooleanVar(value=cur_cfg.get("enabled", True))
        cb_cur = tk.Checkbutton(f_cur, text="Cursor", variable=var_cursor,
                                font=("Sans", 9, "bold"), fg="#C084FC", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#C084FC")
        cb_cur.pack(anchor="w")
        ent_cursor_token = tk.Entry(f_cur, font=("Sans", 8), bg="#141414", fg="#FFFFFF", insertbackground="white", show="•")
        ent_cursor_token.insert(0, cur_cfg.get("token", ""))
        ent_cursor_token.pack(fill="x", pady=2)
        tk.Label(f_cur, text="💡 Cursor Session Token (optional if signed in to Cursor)", font=("Sans", 7), fg="#888888", bg="#1F1F1F").pack(anchor="w")
        tk.Label(f_cur, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#C084FC", bg="#1F1F1F").pack(anchor="w", pady=(4, 2))
        r_cur = tk.Frame(f_cur, bg="#1F1F1F")
        r_cur.pack(anchor="w")
        add_hud_cb(r_cur, "cursor-fast-requests", "Fast Requests")
        add_hud_cb(r_cur, "cursor-monthly-cycle", "Monthly Cycle")

        # 5. Copilot Card
        cop_cfg = pCfg.get("github_copilot", {})
        f_cop = tk.Frame(cards_box, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_cop.pack(fill="x", pady=5)
        var_copilot = tk.BooleanVar(value=cop_cfg.get("enabled", True))
        cb_cop = tk.Checkbutton(f_cop, text="Copilot", variable=var_copilot,
                                font=("Sans", 9, "bold"), fg="#FF5265", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#FF5265")
        cb_cop.pack(anchor="w")
        ent_copilot_token = tk.Entry(f_cop, font=("Sans", 8), bg="#141414", fg="#FFFFFF", insertbackground="white", show="•")
        ent_copilot_token.insert(0, cop_cfg.get("token", ""))
        ent_copilot_token.pack(fill="x", pady=2)
        tk.Label(f_cop, text="💡 GitHub Personal Access Token for Copilot (optional)", font=("Sans", 7), fg="#888888", bg="#1F1F1F").pack(anchor="w")
        tk.Label(f_cop, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#FF5265", bg="#1F1F1F").pack(anchor="w", pady=(4, 2))
        r_cop = tk.Frame(f_cop, bg="#1F1F1F")
        r_cop.pack(anchor="w")
        add_hud_cb(r_cop, "copilot-chat-limit", "Chat Limits")
        add_hud_cb(r_cop, "copilot-completions-rate", "Completions Rate")

        # 4. Gemini Card
        gem_cfg = pCfg.get("gemini", {})
        var_gem = tk.BooleanVar(value=gem_cfg.get("enabled", False))
        f_gem = tk.Frame(cards_box, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_gem.pack(fill="x", pady=5)
        cb_gem = tk.Checkbutton(f_gem, text="Google Gemini API (AI Studio)", variable=var_gem, font=("Sans", 9, "bold"),
                                fg="#38BDF8", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#38BDF8")
        cb_gem.pack(anchor="w")
        ent_gem = tk.Entry(f_gem, font=("Sans", 8), bg="#141414", fg="#FFFFFF", insertbackground="white", show="•")
        ent_gem.insert(0, gem_cfg.get("api_key", ""))
        ent_gem.pack(fill="x", pady=2)
        link_gem = tk.Label(f_gem, text="🔗 Get a free key at Google AI Studio", font=("Sans", 7), fg="#4DA3FF", bg="#1F1F1F", cursor="hand2")
        link_gem.pack(anchor="w")
        link_gem.bind("<Button-1>", lambda e: webbrowser.open("https://aistudio.google.com/app/apikey"))
        tk.Label(f_gem, text="HUD Side Panel Gauges:", font=("Sans", 7, "bold"), fg="#38BDF8", bg="#1F1F1F").pack(anchor="w", pady=(4, 2))
        r_gem = tk.Frame(f_gem, bg="#1F1F1F")
        r_gem.pack(anchor="w")
        add_hud_cb(r_gem, "gemini-flash-rpm", "Flash RPM")
        add_hud_cb(r_gem, "gemini-pro-rpm", "Pro RPM")
        add_hud_cb(r_gem, "gemini-key-status", "Key Status")

        # 4. OpenAI Card
        oa_cfg = pCfg.get("openai", {})
        var_oa = tk.BooleanVar(value=oa_cfg.get("enabled", False))
        f_oa = tk.Frame(cards_box, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_oa.pack(fill="x", pady=5)
        cb_oa = tk.Checkbutton(f_oa, text="OpenAI API (sk-...)", variable=var_oa, font=("Sans", 9, "bold"),
                               fg="#FFFFFF", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#FFFFFF")
        cb_oa.pack(anchor="w")
        ent_oa = tk.Entry(f_oa, font=("Sans", 8), bg="#141414", fg="#FFFFFF", insertbackground="white", show="•")
        ent_oa.insert(0, oa_cfg.get("api_key", ""))
        ent_oa.pack(fill="x", pady=2)

        # 5. Anthropic Claude API Card
        ant_cfg = pCfg.get("anthropic", {})
        var_ant = tk.BooleanVar(value=ant_cfg.get("enabled", False))
        f_ant = tk.Frame(cards_box, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_ant.pack(fill="x", pady=5)
        cb_ant = tk.Checkbutton(f_ant, text="Anthropic Claude API (sk-ant-...)", variable=var_ant, font=("Sans", 9, "bold"),
                                fg="#FFFFFF", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#FFFFFF")
        cb_ant.pack(anchor="w")
        ent_ant = tk.Entry(f_ant, font=("Sans", 8), bg="#141414", fg="#FFFFFF", insertbackground="white", show="•")
        ent_ant.insert(0, ant_cfg.get("api_key", ""))
        ent_ant.pack(fill="x", pady=2)

        # Save Action
        def do_save():
            hidden_list = []
            for gid, v in hud_vars.items():
                if not v.get():
                    hidden_list.append(gid)

            new_cfg = {
                "providers": {
                    "antigravity": {"enabled": var_anti.get()},
                    "claude_pro": {"enabled": var_claude_pro.get(), "token": ent_claude_token.get().strip()},
                    "chatgpt_subscription": {"enabled": var_chatgpt.get(), "token": ent_chatgpt_token.get().strip()},
                    "cursor": {"enabled": var_cursor.get(), "token": ent_cursor_token.get().strip()},
                    "github_copilot": {"enabled": var_copilot.get(), "token": ent_copilot_token.get().strip()},
                    "gemini": {"enabled": var_gem.get() or bool(ent_gem.get().strip()), "api_key": ent_gem.get().strip()},
                    "openai": {"enabled": var_oa.get() or bool(ent_oa.get().strip()), "api_key": ent_oa.get().strip()},
                    "anthropic": {"enabled": var_ant.get() or bool(ent_ant.get().strip()), "api_key": ent_ant.get().strip()}
                },
                "refresh_interval_seconds": 30,
                "hidden_hud_gauges": hidden_list
            }
            save_config(new_cfg)
            close_dlg()
            self.refresh(True)

        btn_save = tk.Button(f_btns, text="Save & Refresh", font=("Sans", 9, "bold"), fg="#121212", bg="#00E699",
                             activebackground="#33FFB5", activeforeground="#121212", relief="flat", padx=14, pady=6, cursor="hand2", command=do_save)
        btn_save.pack(side="left")

        btn_cancel = tk.Button(f_btns, text="Cancel", font=("Sans", 9), fg="#CCCCCC", bg="#2A2A2A",
                               activebackground="#3A3A3A", activeforeground="#FFFFFF", relief="flat", padx=12, pady=6, cursor="hand2", command=close_dlg)
        btn_cancel.pack(side="right")

    def setup_ui(self):
        for widget in self.root.winfo_children():
            if self.settings_dlg and widget == self.settings_dlg:
                continue
            widget.destroy()

        if self.mode == "full":
            self.setup_full_ui()
        else:
            self.setup_hud_ui()

    def setup_full_ui(self):
        self.root.overrideredirect(False)
        self.root.attributes("-topmost", False)
        self.root.resizable(False, False)
        self.root.configure(bg="#181818")

        quota = self.quota or {}
        groups = quota.get("groups", [])

        w = 500
        total_cards_h = sum(36 + len(g.get("buckets", [])) * 48 for g in groups)
        if total_cards_h == 0:
            h = 420
        else:
            h = max(380, min(100 + total_cards_h + 80, 720))
        self.root.geometry(f"{w}x{h}")

        # Footer packed first with side="bottom" to guarantee it never gets cut off
        footer = tk.Frame(self.root, bg="#181818", padx=20, pady=12)
        footer.pack(fill="x", side="bottom")

        btn_row = tk.Frame(footer, bg="#181818")
        btn_row.pack(fill="x")

        self.refresh_btn = tk.Button(btn_row, text="↻ Refresh", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                                     activebackground="#FFFFFF", relief="flat", padx=12, pady=5, cursor="hand2",
                                     command=lambda: self.refresh(True))
        self.refresh_btn.pack(side="left")

        hud_btn = tk.Button(btn_row, text="⤢ HUD Bar", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                            activebackground="#FFFFFF", relief="flat", padx=12, pady=5, cursor="hand2",
                            command=self.toggle_mode)
        hud_btn.pack(side="left", padx=8)

        cfg_btn = tk.Button(btn_row, text="⚙ Settings", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                            activebackground="#FFFFFF", relief="flat", padx=12, pady=5, cursor="hand2",
                            command=self.open_settings)
        cfg_btn.pack(side="left", padx=2)

        close_btn = tk.Button(btn_row, text="✕ Close", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                              activebackground="#FFFFFF", relief="flat", padx=12, pady=5, cursor="hand2",
                              command=self.root.destroy)
        close_btn.pack(side="right")

        main_frame = tk.Frame(self.root, bg="#181818", padx=20, pady=16)
        main_frame.pack(fill="both", expand=True)

        acc_text = f"{quota.get('account', 'Multi-Provider')} • Plan {quota.get('plan', 'Universal')}"
        lbl_acc = tk.Label(main_frame, text=acc_text, font=("Sans", 11, "bold"), fg="#FFFFFF", bg="#181818", anchor="w")
        lbl_acc.pack(fill="x")

        time_status = "(Live)" if not quota.get("from_cache") else f"(Cache {quota.get('cache_age_seconds', 0)}s)"
        time_text = f"Updated at {quota.get('updated_at', 'now')} {time_status}"
        lbl_time = tk.Label(main_frame, text=time_text, font=("Sans", 9), fg="#A0A0A0", bg="#181818", anchor="w")
        lbl_time.pack(fill="x", pady=(2, 8))

        # Update Available Banner
        update_info = quota.get("update", {})
        if update_info.get("update_available"):
            up_box = tk.Frame(main_frame, bg="#00E699", padx=12, pady=7)
            up_box.pack(fill="x", pady=(0, 10))
            new_v = update_info.get("latest_version", "")
            up_lbl = tk.Label(up_box, text=f"New release v{new_v} available", font=("Sans", 9, "bold"), fg="#121212", bg="#00E699")
            up_lbl.pack(side="left")
            d_url = update_info.get("download_url") or "https://github.com/vh2c/ai-gauge/releases/latest"
            btn_up = tk.Button(up_box, text="Download", font=("Sans", 8, "bold"), fg="#121212", bg="#FFFFFF",
                               activebackground="#EEEEEE", activeforeground="#121212", relief="flat", padx=10, pady=2, cursor="hand2", command=lambda: webbrowser.open(d_url))
            btn_up.pack(side="right")

        # Announcement / Free vs PRO Notice Banner (only shown if an announcement message exists)
        announcement = quota.get("announcement")
        if announcement and announcement.get("message"):
            ann_type = announcement.get("type", "info")
            ann_bg = "#1F2937" if ann_type == "info" else "#2D2418"
            ann_border = "#3B82F6" if ann_type == "info" else "#F59E0B"
            ann_badge_col = "#60A5FA" if ann_type == "info" else "#FBBF24"

            ann_box = tk.Frame(main_frame, bg=ann_bg, padx=12, pady=8, highlightbackground=ann_border, highlightthickness=1)
            ann_box.pack(fill="x", pady=(0, 10))
            
            top_row = tk.Frame(ann_box, bg=ann_bg)
            top_row.pack(fill="x")
            
            badge_text = announcement.get("badge", "AVISO")
            lbl_badge = tk.Label(top_row, text=f"[{badge_text}]", font=("Sans", 8, "bold"), fg=ann_badge_col, bg=ann_bg)
            lbl_badge.pack(side="left")
            
            lbl_title = tk.Label(top_row, text=announcement.get("title", ""), font=("Sans", 8, "bold"), fg="#FFFFFF", bg=ann_bg)
            lbl_title.pack(side="left", padx=6)
            
            lbl_msg = tk.Label(ann_box, text=announcement.get("message", ""), font=("Sans", 8), fg="#D1D5DB", bg=ann_bg, anchor="w", justify="left", wraplength=440)
            lbl_msg.pack(fill="x", pady=(4, 6))
            
            if announcement.get("action_label") and announcement.get("action_url"):
                a_url = announcement.get("action_url")
                act_label = announcement.get("action_label", "")
                btn_text = act_label if (act_label.endswith("!") or "→" in act_label) else f"{act_label} →"
                btn_act = tk.Button(ann_box, text=btn_text, font=("Sans", 8, "bold"), fg="#121212", bg=ann_badge_col,
                                    relief="flat", padx=14, pady=4, cursor="hand2", command=lambda: webbrowser.open(a_url))
                btn_act.pack(anchor="center", pady=(2, 4))

        if not groups:
            empty_frame = tk.Frame(main_frame, bg="#1F1F1F", padx=20, pady=20, highlightbackground="#2A2A2A", highlightthickness=1)
            empty_frame.pack(fill="both", expand=True, pady=10)
            tk.Label(empty_frame, text="🤖 No AI Records Found", font=("Sans", 11, "bold"), fg="#FFFFFF", bg="#1F1F1F").pack(pady=(8, 4))
            tk.Label(empty_frame, text="No active local sessions were found (Antigravity, Claude, ChatGPT, Cursor, Copilot).\nConfigure an API key (Gemini, OpenAI, Anthropic) or session token:", font=("Sans", 8.5), fg="#AAAAAA", bg="#1F1F1F", justify="center").pack(pady=(0, 12))
            tk.Button(empty_frame, text="⚙️ Configure Providers and Keys", font=("Sans", 9.5, "bold"), fg="#121212", bg="#00E699",
                      activebackground="#33FFB5", activeforeground="#121212", relief="flat", padx=16, pady=6, cursor="hand2", command=self.open_settings).pack(pady=(0, 6))
            tk.Button(empty_frame, text="🔗 Get a Free Key at Google AI Studio (aistudio.google.com) →", font=("Sans", 8), fg="#38BDF8", bg="#18181C",
                      activebackground="#252530", activeforeground="#38BDF8", relief="flat", padx=10, pady=4, cursor="hand2", command=lambda: webbrowser.open("https://aistudio.google.com/app/apikey")).pack()

        cfg = load_config()
        sec_colors = cfg.get("section_colors", {})
        for g in groups:
            prov = f" [{g.get('provider')}]" if g.get('provider') else ""
            gname_lower = g.get("name", "").lower()
            prov_lower = g.get("provider", "").lower()
            
            if "cursor" in gname_lower or "cursor" in prov_lower:
                accent_col = sec_colors.get("cursor", "#C084FC")
            elif "copilot" in gname_lower or "copilot" in prov_lower or "github" in prov_lower:
                accent_col = sec_colors.get("github_copilot", "#FF5265")
            elif ("claude" in gname_lower or "claude" in prov_lower) and "claude and gpt" not in gname_lower:
                accent_col = sec_colors.get("claude_pro", "#D78C68")
            elif "chatgpt" in gname_lower or "chatgpt" in prov_lower:
                accent_col = sec_colors.get("chatgpt_subscription", "#8AE39A")
            elif "studio" in prov_lower or "gemini api" in gname_lower or "gemini" in prov_lower:
                accent_col = sec_colors.get("gemini", "#67E8F9")
            else:
                accent_col = sec_colors.get("antigravity", "#8FBCFF")

            lbl_g = tk.Label(main_frame, text=(g.get("name", "Modelos") + prov).upper(), font=("Sans", 8, "bold"), fg=accent_col, bg="#181818", anchor="w")
            lbl_g.pack(fill="x", pady=(4, 2))

            card = tk.Frame(main_frame, bg="#1F1F1F", bd=1, relief="solid", padx=14, pady=10)
            card.configure(highlightbackground="#2C2C2C", highlightthickness=1)
            card.pack(fill="x", pady=(0, 10))

            for idx, b in enumerate(g.get("buckets", [])):
                if idx > 0:
                    sep = tk.Frame(card, bg="#282828", height=1)
                    sep.pack(fill="x", pady=6)

                row1 = tk.Frame(card, bg="#1F1F1F")
                row1.pack(fill="x")

                bname = tk.Label(row1, text=b.get("name", ""), font=("Sans", 9), fg="#FFFFFF", bg="#1F1F1F")
                bname.pack(side="left")

                pct = b.get("remaining_pct", 100)
                reset_str = f" • {b.get('reset_in')}" if b.get("reset_in") else ""
                val_text = f"{pct}%{reset_str}"
                val_col = status_color(pct, accent_col)
                bval = tk.Label(row1, text=val_text, font=("Monospace", 9, "bold"), fg=val_col, bg="#1F1F1F")
                bval.pack(side="right")

                bar_canvas = tk.Canvas(card, bg="#2D2D2D", height=6, highlightthickness=0, bd=0)
                bar_canvas.pack(fill="x", pady=(4, 2))
                bar_w = 500 - 40 - 28
                fill_w = max(4, int(bar_w * (pct / 100.0)))
                bar_canvas.create_rectangle(0, 0, fill_w, 6, fill=val_col, outline="")
        close_btn.pack(side="right")

        mid = get_machine_id()
        donate_url = f"https://ai-gauge.vh2c.com.br/donate?mid={mid}" if mid else "https://ai-gauge.vh2c.com.br/donate"
        brand_lbl = tk.Label(footer, text="⚡ AI Gauge  •  Developed by vh2c.com.br", font=("Sans", 8),
                             fg="#9CA3AF", bg="#181818", cursor="hand2")
        brand_lbl.pack(pady=(8, 2))
        brand_lbl.bind("<Button-1>", lambda e: webbrowser.open(donate_url))

    def setup_hud_ui(self):
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.configure(bg="#141414")

        quota = self.quota or {}
        items = get_gauge_items(quota)
        is_vert = (self.orientation == "vertical")

        if is_vert:
            w = 104
            h = 28 + max(1, len(items)) * 96 + 18
        else:
            w = 28 + max(1, len(items)) * 96 + 10
            h = 108

        sw = self.root.winfo_screenwidth()
        sh = self.root.winfo_screenheight()
        if is_vert:
            x = sw - w - 24
            y = (sh - h) // 2
        else:
            x = (sw - w) // 2
            y = sh - h - 36
        self.root.geometry(f"{w}x{h}+{x}+{y}")

        self._drag_data = {"x": 0, "y": 0}
        def start_drag(event):
            self._drag_data["x"] = event.x
            self._drag_data["y"] = event.y
        def do_drag(event):
            dx = event.x - self._drag_data["x"]
            dy = event.y - self._drag_data["y"]
            nx = self.root.winfo_x() + dx
            ny = self.root.winfo_y() + dy
            self.root.geometry(f"+{nx}+{ny}")

        canvas = tk.Canvas(self.root, bg="#141414", highlightbackground="#2A2A2A", highlightthickness=1, bd=0)
        canvas.pack(fill="both", expand=True)
        canvas.bind("<Button-1>", start_drag)
        canvas.bind("<B1-Motion>", do_drag)
        canvas.bind("<Double-Button-1>", lambda e: self.toggle_mode())

        def make_icon(x, y, txt, tip, action):
            t = canvas.create_text(x, y, text=txt, font=("Sans", 9, "bold"), fill="#999999", tags="btn")
            canvas.tag_bind(t, "<Button-1>", lambda e: action())
            canvas.tag_bind(t, "<Enter>", lambda e: canvas.itemconfig(t, fill="#FFFFFF"))
            canvas.tag_bind(t, "<Leave>", lambda e: canvas.itemconfig(t, fill="#999999"))

        if is_vert:
            make_icon(14, 14, "✕", "Close", self.root.destroy)
            make_icon(34, 14, "⇄", "Toggle Orientation", self.toggle_orientation)
            make_icon(54, 14, "⊞", "Modo Completo", self.toggle_mode)
            make_icon(74, 14, "⚙", "Configurar", self.open_settings)
            make_icon(92, 14, "↻", "Atualizar", lambda: self.refresh(True))
        else:
            make_icon(14, 14, "✕", "Close", self.root.destroy)
            make_icon(14, 34, "⇄", "Toggle Orientation", self.toggle_orientation)
            make_icon(14, 54, "⊞", "Modo Completo", self.toggle_mode)
            make_icon(14, 74, "⚙", "Configurar", self.open_settings)
            make_icon(14, 94, "↻", "Atualizar", lambda: self.refresh(True))

        if is_vert:
            cur_y = 30
            for item in items:
                self.draw_gauge(canvas, 52, cur_y + 44, item)
                cur_y += 96
            if quota.get("update", {}).get("update_available"):
                t_id = canvas.create_text(52, h - 8, text="● NEW RELEASE", font=("Sans", 7, "bold"), fill="#8AE39A")
                d_url = quota.get("update", {}).get("download_url") or "https://github.com/vh2c/ai-gauge/releases/latest"
                canvas.tag_bind(t_id, "<Button-1>", lambda e: webbrowser.open(d_url))
            else:
                mid = get_machine_id()
                donate_url = f"https://ai-gauge.vh2c.com.br/donate?mid={mid}" if mid else "https://ai-gauge.vh2c.com.br/donate"
                t_brand = canvas.create_text(52, h - 8, text="vh2c.com.br", font=("Sans", 7), fill="#555555")
                canvas.tag_bind(t_brand, "<Button-1>", lambda e: webbrowser.open(donate_url))
        else:
            cur_x = 28
            for item in items:
                self.draw_gauge(canvas, cur_x + 48, 54, item)
                cur_x += 96
            if quota.get("update", {}).get("update_available"):
                t_id = canvas.create_text(w - 44, h - 8, text="● NEW RELEASE", font=("Sans", 7, "bold"), fill="#8AE39A")
                d_url = quota.get("update", {}).get("download_url") or "https://github.com/vh2c/ai-gauge/releases/latest"
                canvas.tag_bind(t_id, "<Button-1>", lambda e: webbrowser.open(d_url))

    def draw_gauge(self, canvas, cx, cy, item):
        pct = item.get("pct", 100)
        col = status_color(pct, item.get("accent"))
        inactive_col = "#333333"

        r_outer = 27
        r_inner = 20.5
        r_center = 18
        total_ticks = 36
        active_ticks = int(round(total_ticks * max(0, min(100, pct)) / 100.0))

        for i in range(total_ticks):
            frac = i / float(total_ticks)
            angle = -math.pi / 2.0 + frac * 2.0 * math.pi
            x1 = cx + math.cos(angle) * r_inner
            y1 = cy + math.sin(angle) * r_inner
            x2 = cx + math.cos(angle) * r_outer
            y2 = cy + math.sin(angle) * r_outer
            c = col if i < active_ticks else inactive_col
            canvas.create_line(x1, y1, x2, y2, fill=c, width=2, capstyle="round")

        canvas.create_oval(cx - r_center, cy - r_center, cx + r_center, cy + r_center, fill=col, outline="")

        font_sz = 9 if pct >= 100 else 10
        canvas.create_text(cx, cy, text=f"{pct}%", font=("Monospace", font_sz, "bold"), fill="#FFFFFF")
        canvas.create_text(cx, cy - r_outer - 7, text=item.get("title", ""), font=("Sans", 8, "bold"), fill="#FFFFFF")
        canvas.create_text(cx, cy + r_outer + 8, text=item.get("model", ""), font=("Sans", 9, "bold"), fill="#FFFFFF")

        rt = item.get("reset_in", "")
        if rt:
            canvas.create_text(cx, cy + r_outer + 19, text=rt, font=("Sans", 8), fill="#999999")

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
