# Installing AI Gauge

This guide covers installation on **macOS, Windows and Linux**, including what to do about the security warnings
you may see. It is written so that a person, or an AI assistant helping that person, can follow it step by step.

- [Requirements](#requirements)
- [Why you see a security warning](#why-you-see-a-security-warning)
- [Download and verify](#download-and-verify)
- [macOS](#macos) · [Windows](#windows) · [Linux](#linux)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Install with an AI assistant](#install-with-an-ai-assistant)

---

## Requirements

| Platform | Supported versions | Node.js |
| :--- | :--- | :--- |
| 🍏 **macOS** | Apple Silicon (M1 or newer): macOS 11 or later. Intel: macOS 13 or later. | **Required: Node.js 18 or later, installed by you** (see [macOS](#macos), step 1). |
| 🪟 **Windows** | Windows 10 or 11 (64-bit). | Included in `AI-Gauge-Setup.exe`. The ZIP installer downloads a portable copy automatically. |
| 🐧 **Linux** | Ubuntu, Debian, Fedora, Arch, Mint and similar. | Downloaded automatically by the installer (portable copy, no `sudo` needed). |

Not supported: macOS 10.15 (Catalina) and older, Windows 8 and older.

---

## Why you see a security warning

AI Gauge is free, open-source software (MIT license). Its installers are **not yet code-signed** and the macOS app is
**not notarized by Apple**, because that requires paid developer certificates. Because of that:

- **macOS** blocks the first launch of the app.
- **Windows** may show a blue **"Windows protected your PC"** (SmartScreen) screen for the installer.

This does not mean the file is dangerous. It means the system does not recognise the publisher yet. You can check that
the file is the one we published by [verifying its checksum](#download-and-verify), and you can read all the source
code in this repository.

---

## Download and verify

Always download from the official **[Releases page](https://github.com/vh2c/ai-gauge/releases/latest)**.

| Platform | File |
| :--- | :--- |
| macOS | [`AI-Gauge-macOS-vh2c.zip`](https://github.com/vh2c/ai-gauge/releases/latest/download/AI-Gauge-macOS-vh2c.zip) |
| Windows (recommended) | [`AI-Gauge-Setup.exe`](https://github.com/vh2c/ai-gauge/releases/latest/download/AI-Gauge-Setup.exe) |
| Windows (portable ZIP) | [`AI-Gauge-Windows-vh2c.zip`](https://github.com/vh2c/ai-gauge/releases/latest/download/AI-Gauge-Windows-vh2c.zip) |
| Linux | [`AI-Gauge-Linux-vh2c.zip`](https://github.com/vh2c/ai-gauge/releases/latest/download/AI-Gauge-Linux-vh2c.zip) |
| Checksums | [`SHA256SUMS.txt`](https://github.com/vh2c/ai-gauge/releases/latest/download/SHA256SUMS.txt) |

**Verify the download (recommended).** Open `SHA256SUMS.txt`, find the line for your file, and compare it with the
checksum of the file you downloaded. The two values must be identical.

- macOS / Linux (Terminal), from the folder where the file was downloaded:
  ```bash
  shasum -a 256 AI-Gauge-macOS-vh2c.zip
  ```
  (on Linux you can also use `sha256sum AI-Gauge-Linux-vh2c.zip`)
- Windows (PowerShell), from the folder where the file was downloaded:
  ```powershell
  Get-FileHash .\AI-Gauge-Setup.exe -Algorithm SHA256
  ```

If the values do not match, **do not install the file**: download it again, and open an issue if it still differs.

---

## macOS

### Fastest way: one command (no security warning)

Open **Terminal** (⌘ + Space, type *Terminal*, Enter), paste this and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/vh2c/ai-gauge/main/macos/get-ai-gauge.sh | bash
```

It checks your Mac, downloads the latest release, **verifies its SHA-256 checksum**, installs **AI Gauge.app** in
`/Applications` (the old version goes to the Trash) and opens it. It never uses `sudo` and never changes security settings.

**Why there is no warning:** files downloaded with `curl` are not flagged as "downloaded from the internet", so macOS
does not block them. Files downloaded in a browser are flagged (see [Downloaded it in the browser?](#downloaded-it-in-the-browser)).

**Prefer to read it first?** The script is short: [`macos/get-ai-gauge.sh`](macos/get-ai-gauge.sh). You can download it,
read it, and run it with `bash get-ai-gauge.sh`.

**To update to a newer version later:** click **Update now** in the green "New release available" banner inside AI Gauge
(v1.1.4 and later), or run the same command again. The button asks for confirmation, then downloads the new release,
verifies its SHA-256 checksum, closes the app, installs it (the old version goes to the Trash) and opens it again. It runs a
script that is bundled inside the app, so nothing but the release package is downloaded. If it cannot update in place (for
example, the app is running from the Downloads folder or from a read-only location), it offers the release page instead.

The script also tells you if Node.js is missing. If so, see the next section.

### Node.js 18 or later (required, install once)

AI Gauge needs Node.js on the Mac. **Without it the app cannot collect any quota data.** Check whether you already
have it:

```bash
node -v
```

If this prints a version such as `v20.11.0` or higher, you are done. Otherwise install Node.js with **one** of:

- **Installer (simplest):** download the **LTS** `.pkg` from <https://nodejs.org> and run it.
- **Homebrew:** `brew install node`

Close and reopen Terminal afterwards and run `node -v` again to confirm. Then open AI Gauge again.

### Downloaded it in the browser?

If you downloaded `AI-Gauge-macOS-vh2c.zip` in a browser, macOS blocks the first launch because the app is **not
notarized by Apple**. You will see *"Apple could not verify AI Gauge.app is free of malware..."* with only **Done** and
**Move to Trash**. Do **not** move it to the Trash. Instead:

1. Double-click the ZIP to extract it, and drag **AI Gauge.app** into the **Applications** folder.
2. Use **Option A** (recommended). It only affects AI Gauge.

**Option A: Terminal (most reliable)**

```bash
xattr -cr "/Applications/AI Gauge.app" && open "/Applications/AI Gauge.app"
```

This removes the "downloaded from the internet" flag from AI Gauge only, and opens it.

**Option B: System Settings**

1. Double-click **AI Gauge** in Applications. macOS shows the message above. Click **Done**.
2. Open **System Settings → Privacy & Security** and scroll down to the **Security** section.
3. Next to *"AI Gauge" was blocked*, click **Open Anyway**, then confirm with your password or Touch ID.

On recent macOS versions, **right-click → Open** is no longer enough.

**You need to repeat this for every new version you download in a browser.** The one-command method above avoids it.

From then on, open AI Gauge normally from Spotlight or Launchpad. The first time it starts, AI Gauge detects the tools you already use,
starts monitoring them right away and shows one short welcome message (with a button to choose what to monitor, if you
want). A gauge icon appears in the menu bar, and the floating HUD opens on screen. The running version is shown next to
the title in the full window.

*Developers: to build from source instead, clone the repository, then run `./install.sh` inside the `macos/`
folder (needs the Xcode Command Line Tools).*

---

## Windows

### Fastest way: one command (usually no SmartScreen screen)

Open **PowerShell** (Start menu → type *PowerShell* → Enter), paste this and press Enter:

```powershell
irm https://raw.githubusercontent.com/vh2c/ai-gauge/main/windows/get-ai-gauge.ps1 | iex
```

It downloads the latest `AI-Gauge-Setup.exe`, **verifies its SHA-256 checksum**, and starts the installer. If the
checksum does not match, it runs nothing. Files downloaded with PowerShell are normally not flagged as "downloaded from
the internet", so Windows usually does not show the **"Windows protected your PC"** screen. If your antivirus or
Windows still warns, use Option 1 below and the steps there.

**To update later:** click **Update now** in the banner inside AI Gauge (v1.1.4 and later; it installs silently and reopens the app), or run the same command again. You can read the script first: [`windows/get-ai-gauge.ps1`](windows/get-ai-gauge.ps1).

### Option 1: Installer (recommended if you download in the browser)

1. Download `AI-Gauge-Setup.exe` and (optionally) [verify it](#download-and-verify).
2. Double-click it. If you see **"Windows protected your PC"**:
   1. Click **More info**.
   2. Click **Run anyway**.
3. Follow the installer. It does **not** need administrator rights, includes Node.js, creates a Desktop shortcut and a
   Start Menu entry, and replaces any previous version while keeping your settings.
4. Leave **Launch AI Gauge** ticked on the last page.

### Option 2: Portable ZIP

1. Download `AI-Gauge-Windows-vh2c.zip`, then **right-click it → Extract All**. Do not run files from inside the ZIP.
2. Open the extracted folder and double-click **`install.bat`**. If SmartScreen appears, use **More info → Run anyway**.
3. If Node.js is missing, the installer downloads a portable copy (about 30 MB, once, checked with SHA-256).
4. Use the new **AI Gauge** shortcut on the Desktop or in the Start Menu.

---

## Linux

1. Download `AI-Gauge-Linux-vh2c.zip` and (optionally) [verify it](#download-and-verify).
2. In a terminal:
   ```bash
   unzip AI-Gauge-Linux-vh2c.zip -d AI-Gauge-Linux
   cd AI-Gauge-Linux
   ./linux/install.sh
   ```
3. The installer may ask for your password (`sudo`) only to install `python3` / `python3-tk` if they are missing. It
   downloads a portable Node.js, so you do not need to install Node yourself.
4. Start it from your applications menu (**AI Gauge**) or run `gemini-gauge` (or `quota-hub`) in a terminal. For a text-only view over SSH, run `gemini-gauge --cli`.

---

## Troubleshooting

| Problem | What to do |
| :--- | :--- |
| **macOS: "AI Gauge cannot be opened"** (only an OK button) | Make sure the app is in **/Applications**, then run the [Option A command](#downloaded-it-in-the-browser). Also check **Apple menu → About This Mac**: you need macOS 11+ on Apple Silicon or macOS 13+ on Intel. |
| **macOS: the app shows no quota data** | Node.js is missing or too old. Run `node -v` (must be 18 or later) and follow [step 1](#nodejs-18-or-later-required-install-once). Quit and reopen the app. |
| **macOS: still blocked after Option A** | In Terminal run `open -a "/Applications/AI Gauge.app" 2>&1`, then `"/Applications/AI Gauge.app/Contents/MacOS/AIGauge" 2>&1 \| head -20`, and include the output when you [open an issue](https://github.com/vh2c/ai-gauge/issues). |
| **Windows: no "Run anyway" button** | Click **More info** first. The button appears only after that. |
| **Windows: the installer or app does nothing** | Look for the log file at `%TEMP%\ai_gauge_error.log` (paste that path into the Explorer address bar) and include it in an issue. |
| **Windows: antivirus blocks the file** | Check the checksum first. If it matches, restore the file from quarantine or add an exception for the AI Gauge folder (`%LOCALAPPDATA%\AIGauge`). |
| **Linux: no window appears** | Run `gemini-gauge` in a terminal to see the error. The most common cause is a missing `python3-tk` (`sudo apt install python3-tk` on Debian/Ubuntu). |
| **A provider shows "Outdated"** (amber text instead of the reset time) | AI Gauge could not reach that service and is showing numbers from an old local cache. The usual cause is an expired login. **Claude:** in a terminal run `claude auth status`; if it says `"loggedIn": false`, run `claude` and sign in with `/login`. **ChatGPT:** sign in again in the ChatGPT / Codex app. The numbers update within a minute of signing in. |
| **No data for a provider** | AI Gauge detects the apps you already use (Claude, ChatGPT, Cursor, Copilot, Antigravity) automatically. For Gemini, OpenAI or Anthropic API keys, open **Settings** and paste the key. |

---

## What AI Gauge detects automatically

AI Gauge reads the logins you **already have** on your computer, so there is usually nothing to paste. If a provider does not appear,
this table tells you what it looks for. You can always add a key or token by hand in **Settings**.

| Provider | Where it looks |
| :--- | :--- |
| **Antigravity** | The running Antigravity IDE (or a background probe when it is closed). All systems. |
| **Claude** | macOS: the Claude Code login in the Keychain. Windows and Linux: the Claude Code login file `~/.claude/.credentials.json` (`%USERPROFILE%\.claude\.credentials.json` on Windows). Sign in once with Claude Code. |
| **ChatGPT** | The Codex / ChatGPT login file `~/.codex/auth.json`. |
| **Cursor** | Cursor's local data folder, when Cursor is installed and signed in. |
| **GitHub Copilot** | Your GitHub CLI login (`gh auth token`) or the Copilot token files, when VS Code with Copilot is installed. |
| **Gemini, OpenAI, Anthropic API keys** | Paste the key in **Settings**. On Windows, the keys in the `GEMINI_API_KEY`, `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` environment variables are picked up the first time the app runs. |

Detection happens when the app starts for the first time. If you install a tool or sign in **after** that, open **Settings** and enable it.

---

## Uninstall

- **macOS:** quit AI Gauge, then drag **AI Gauge.app** from Applications to the Trash. To also remove your settings:
  `rm -rf ~/.config/UniversalAIQuota`
- **Windows:** **Settings → Apps → AI Gauge → Uninstall**, or Start Menu → **Uninstall AI Gauge**. You are asked
  whether to keep your settings.
- **Linux:** delete `~/.local/share/universal-ai-quota`, the launchers `gemini-gauge` and
  `quota-hub` in `~/.local/bin` (and in `/usr/local/bin` if present), and `gemini-gauge.desktop` in
  `~/.local/share/applications`.
  Settings live in `~/.config/UniversalAIQuota`.

---

## Install with an AI assistant

If you would rather have an AI assistant do it (or help a relative who is not comfortable with Terminal), you can.
It works best with an assistant that can run commands on the computer (for example Claude Code or a similar
coding agent). With a chat-only assistant, ask it to guide you step by step instead.

**Copy and paste this prompt, filling in your operating system:**

```text
I want to install AI Gauge (https://github.com/vh2c/ai-gauge) on my computer. My operating system is: <macOS / Windows / Linux>.

Read the official install guide and follow it exactly:
https://raw.githubusercontent.com/vh2c/ai-gauge/main/INSTALL.md

Rules:
1. On macOS, prefer the one-command installer from the guide (curl ... get-ai-gauge.sh | bash), which verifies the checksum itself; on Windows, the PowerShell one-liner. Otherwise download only from https://github.com/vh2c/ai-gauge/releases/latest and verify the SHA-256 checksum against SHA256SUMS.txt before running anything.
2. Before each command, show it to me, explain what it does in one sentence, and wait for my OK for anything that changes the system.
3. Never disable Gatekeeper, SmartScreen, antivirus, SIP or any other system protection, and do not use sudo or administrator rights unless the guide says so.
4. Only run xattr on "/Applications/AI Gauge.app", never on other files or folders.
5. If a step fails, show me the exact error and use the Troubleshooting section of the guide. Do not improvise destructive fixes.
6. On macOS, check that Node.js 18 or later is installed (node -v) and help me install it if not.
7. At the end, confirm that AI Gauge is running and give me a short summary of what was installed and where.
```

If the assistant cannot open links, paste the contents of this file into the chat and ask it to follow it.

**Why these rules matter:** AI Gauge is safe to open after the first-launch step, but turning off the operating
system's protections to "make it work" exposes the whole computer. A good assistant should never need to do that.
