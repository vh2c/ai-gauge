<div align="center">

# ⚡ AI Gauge

### Multi-Platform AI Usage Monitor & Rate Limit Tracker for macOS, Linux & Windows
**Track your Claude, ChatGPT, Cursor, GitHub Copilot, Gemini and Antigravity usage limits in one desktop widget.**

**Developed by [VH2C](https://vh2c.com.br)**

[![Total Downloads](https://img.shields.io/github/downloads/vh2c/ai-gauge/total.svg?style=flat-square&logo=github&color=00E699)](https://github.com/vh2c/ai-gauge/releases)
[![Latest Release](https://img.shields.io/github/v/release/vh2c/ai-gauge?style=flat-square&color=38BDF8)](https://github.com/vh2c/ai-gauge/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey.svg?style=flat-square)](#)
[![Powered by VH2C](https://img.shields.io/badge/Developed%20by-vh2c.com.br-00C9FF?style=flat-square)](https://vh2c.com.br)

<br/>

<img src="assets/icon_1024.png" width="180" height="180" alt="AI Gauge Icon" />

<br/>

**AI Gauge** is a lightweight, high-performance desktop widget (menu bar / floating HUD) that monitors, in real time, the usage quotas, rate limits (RPM/TPM) and reset windows of your AI models on macOS, Linux and Windows. It works **completely independently of any IDE**, bringing **Antigravity**, **Claude**, **ChatGPT**, **Cursor**, **GitHub Copilot (VS Code)** and **Gemini** together in a single panel.

Ever hit the **Claude usage limit**, the **ChatGPT message cap** or ran out of **Cursor fast requests** without warning? AI Gauge shows how much you have left, and when it resets, before it gets in your way.

> 💡 **Zero-Config Detection (Plug & Play)**: If you already use these apps on your computer, AI Gauge detects the local sessions 100% automatically. No need to type tokens or passwords for **Antigravity**, **Claude**, **ChatGPT**, **Cursor** or **Copilot**!

</div>

---

## 📦 Ready-to-Use Downloads (v1.1)

For testers and non-technical users: **no need to compile any code**. Just download the package for your operating system:

| Platform | Package (.zip) | Size | How to Install |
| :--- | :--- | :---: | :--- |
| 🍏 **macOS** | [**AI-Gauge-macOS-vh2c.zip**](releases/v1.1/AI-Gauge-macOS-vh2c.zip?raw=true) | `2.8 MB` | Extract and drag **AI Gauge.app** to the `/Applications` folder, or run `./install.sh`. |
| 🪟 **Windows** | [**AI-Gauge-Windows-vh2c.zip**](releases/v1.1/AI-Gauge-Windows-vh2c.zip?raw=true) | `0.2 MB` | Extract the ZIP and double-click **`install.bat`**. Portable Node.js is downloaded automatically. |
| 🐧 **Linux** | [**AI-Gauge-Linux-vh2c.zip**](releases/v1.1/AI-Gauge-Linux-vh2c.zip?raw=true) | `0.6 MB` | Extract the ZIP and run **`./linux/install.sh`** in a terminal. |

---

## 🌟 Key Features and HUD Sections

The information in the floating side HUD is grouped by app/provider, each with its own accent color:

1. **`Antigravity`** *(Pastel Blue `#8FBCFF` - dedicated IDE)*:
   - Direct monitoring of the **Google Antigravity IDE** ecosystem (live or headless).
   - **Gemini**: Weekly quota and 5-hour window.
   - **Claude/GPT**: Internal third-party quota (Opus 5.5, Sonnet 5.5, GPT-OSS 120B).
   - **Argon**: Dedicated weekly quota for Gemini 4 Argon WTU.
   - *Authentication:* **Zero-Config** (reads directly from the IDE process/environment).

2. **`Claude`** *(Terracotta Coral `#D78C68` - Anthropic desktop app)*:
   - Monitors your official Claude account and subscription (Pro / Team).
   - **5 Hours Limit**: Rolling 5-hour window of the current session.
   - **Weekly Limit**: Weekly quota with a countdown to renewal.
   - *Authentication:* **Zero-Config** (captured from the macOS Keychain, with automatic refresh of expired tokens).

3. **`ChatGPT`** *(Mint Green `#8AE39A` - OpenAI desktop app)*:
   - Monitors access to your official ChatGPT account (Free, Plus, Pro, Team).
   - **GPT-4o (3h / Active Quota)**: Message window and rate limit.
   - **o1 Reasoning (Weekly)**: Weekly quota for advanced reasoning models.
   - *Authentication:* **Zero-Config** (automatically detects the app session in `~/.codex/auth.json`).

4. **`Cursor`** *(Neon Purple `#A855F7` - Cursor IDE)*:
   - Monitors the quotas of your Cursor subscription (Pro / Business / Fast Requests).
   - **Fast Requests**: Monthly quota of fast requests to premium models (Claude 3.5 Sonnet & GPT-4o).
   - **Monthly Cycle**: Countdown to the renewal of your monthly billing quota.
   - *Authentication:* **Zero-Config** (automatic extraction from Cursor's local storage in `state.vscdb`).

5. **`Copilot`** *(Vibrant Coral `#FF5265` - Visual Studio Code)*:
   - Monitors the status and limits of **Copilot** in VS Code.
   - **Copilot Chat & Model Limits**: Chat message quota and access to Claude 3.5 Sonnet / GPT-4o.
   - **Completions Rate Limits**: Real-time code generation rate limits.
   - *Authentication:* **Zero-Config** (detects the VS Code environment, `gh` CLI tokens or local credentials).

6. **`Gemini`** *(White/Silver `#EBEBEB` - Google AI Studio API)*:
   - Monitoring of direct developer API keys.
   - **Flash RPM & Pro RPM**: Requests-per-minute limits and key status.
   - *Authentication:* Requires an API key (`AIzaSy...`) obtained from [Google AI Studio](https://aistudio.google.com).

---

## ❓ Why AI Gauge?

- **One place for every AI quota:** Claude (Pro/Team), ChatGPT (Free/Plus/Pro/Team), Cursor, GitHub Copilot, Gemini API and Google Antigravity.
- **No setup for most providers:** local sessions are detected automatically (zero-config), with no passwords or tokens to paste.
- **Always visible:** a floating HUD or full window with fuel-style gauges, so you know when to slow down or switch models.
- **Private by design:** your keys, prompts and code never leave your machine. See [Telemetry & Privacy](#-telemetry--privacy).
- **Open source (MIT)** and available for macOS, Windows and Linux.

---

## 🧙‍♂️ Welcome Wizard & Auto-Scan (Onboarding Wizard)

When you install or launch **AI Gauge** for the first time, the smart wizard automatically scans your system:
* **Provider Scan:** Identifies whether **Antigravity**, **Claude** (Claude Code/Keychain) and **ChatGPT** (Desktop session) are already present on your machine.
* **Intuitive Initial Selection:** Shows a clean quick-setup window asking which quotas you want to monitor in your Cockpit.
* **Total Flexibility:** You can enable or disable providers at any time later through **Settings (⌘,)** or the status bar icon.
* **Terminal / CLI Mode:** The install scripts (`install.sh` / `install.ps1`) also include the interactive wizard in the terminal!

---

## 🔋 How to Read the Gauges (Fuel Scale)

All the analog dials in AI GAUGE work like a **battery or fuel gauge**:
* **100%** = Full tank / Quota fully available.
* **0%** = Quota exhausted.

> ℹ️ **Difference from official screens (such as Claude.ai):**
> Apps like Claude express consumption as **% USED** (*e.g. "5% used"*).
> In AI GAUGE, that is equivalent to **95% AVAILABLE**.

* **Green (`#00E699`)**: Healthy quota (50% – 100% remaining).
* **Amber (`#F5A623`)**: Moderate usage (20% – 49% remaining).
* **Red (`#FF4D4F`)**: Low-quota alert (< 20% remaining).

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Cmd + M` (Mac) / `Ctrl + M` (Linux/Win) | Toggle between **Full Window** and **Floating HUD** |
| `Cmd + O` (Mac) / `Ctrl + O` (Linux/Win) | Toggle HUD orientation (**Vertical** / **Horizontal**) |
| `Cmd + R` (Mac) / `Ctrl + R` (Linux/Win) | Refresh all metrics immediately |
| `Cmd + ,` (Mac) / `Ctrl + ,` (Linux/Win) | Open the **Settings (⚙️)** screen |
| `Cmd + W` / `Esc` | Hide or close the window |

---

## 🚀 Quick Install

### 🍏 macOS (Apple Silicon with macOS 11+ · Intel with macOS 13+)
1. Download the package: [**AI-Gauge-macOS-vh2c.zip**](releases/v1.1/AI-Gauge-macOS-vh2c.zip?raw=true)
2. Extract the ZIP and move **`AI Gauge.app`** to the `/Applications` folder (or run `./install.sh`).
3. **First launch:** the app is not notarized by Apple, so macOS blocks the first launch. Run this once in Terminal:
   ```bash
   xattr -cr "/Applications/AI Gauge.app" && open "/Applications/AI Gauge.app"
   ```
   Alternative: try to open the app, then go to **System Settings → Privacy & Security → Open Anyway**. (On recent macOS versions, "right-click → Open" is not enough.)
4. From then on, open it from Spotlight or Launchpad.

*Or build directly from source:*
```bash
git clone https://github.com/vh2c/ai-gauge.git
cd ai-gauge/ai_gauge_app/macos
./install.sh
```

---

### 🐧 Linux (Ubuntu, Debian, Fedora, Arch, Mint)
1. Download the package: [**AI-Gauge-Linux-vh2c.zip**](releases/v1.1/AI-Gauge-Linux-vh2c.zip?raw=true)
2. Extract the archive and run the self-contained script:
```bash
unzip AI-Gauge-Linux-vh2c.zip -d AI-Gauge-Linux
cd AI-Gauge-Linux
./linux/install.sh
```

---

### 🪟 Windows (Windows 10 / 11)
**Recommended option (1 click):** download **`AI-Gauge-Setup.exe`** from the [Releases](https://github.com/vh2c/ai-gauge/releases/latest) page and run it. It already includes Node.js, does not ask for administrator rights, creates the shortcuts and replaces previous versions.

**Alternative option (ZIP):**
1. Download the package: [**AI-Gauge-Windows-vh2c.zip**](releases/v1.1/AI-Gauge-Windows-vh2c.zip?raw=true)
2. Extract the ZIP (do not run it from inside the ZIP).
3. Double-click **`install.bat`**. No administrator rights or pre-installed Node.js needed: if it is missing, the installer downloads a portable Node.js (~30 MB, one time only, SHA-256 verified).
4. Shortcuts are created on the Desktop and in the Start Menu. A previous version is removed automatically and your settings are kept.
5. To uninstall: **Settings → Apps** (or Start Menu → *Uninstall AI Gauge*).

---

## 📊 Telemetry & Privacy

AI Gauge only sends anonymous pings to check for new versions and notices, and to count users globally:
- **When**: a launch ping (at most every 6 hours) and, at most once per hour, a notice/version check that does not count as a new launch.
- **What is sent**: An anonymous machine hash (`machine_id`), operating system (`macOS`/`Linux`/`Windows`), architecture and app version.
- **How to turn it off**: set `"telemetry": false` in `config.json` (without telemetry, notices are no longer received either).
- **What is NEVER sent**: No API key, prompt, token, code, project or personal data.

---

## 💼 Custom AI Solutions for Business

Need autonomous AI agents, complex workflow orchestration or custom development for your organization?

Get to know **[VH2C](https://vh2c.com.br)** or talk to our engineering team.

---

## 📄 License

Distributed under the **MIT** license. See the `LICENSE` file for more information.  
Developed with ⚡ by **[VH2C](https://vh2c.com.br)**.
