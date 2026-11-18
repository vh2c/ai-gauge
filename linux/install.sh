#!/usr/bin/env bash
set -e

echo "=========================================================="
echo " ⚡ AI Gauge - Smart AI Quota Monitor (Linux)"
echo " Developed by VH2C • https://vh2c.com.br"
echo "=========================================================="
echo ""

TARGET_DIR="${HOME}/.local/share/universal-ai-quota"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor/512x512/apps"

mkdir -p "${TARGET_DIR}" "${TARGET_DIR}/bin" "${BIN_DIR}" "${APP_DIR}" "${ICON_DIR}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 1. Detect architecture
ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
    x86_64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l) ARCH="armv7l" ;;
    *) ARCH="x64" ;;
esac

# 2. Helper to run commands with sudo if not root
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        echo "🔐 Requesting administrator permission (sudo) to install dependencies..."
        sudo "$@"
    else
        echo "❌ Root/sudo permission is required to install system packages."
        return 1
    fi
}

# 3. Detect Distro Package Manager
PKG_MANAGER=""
if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
fi

# 4. Check and install Python 3
if ! command -v python3 >/dev/null 2>&1; then
    echo "📦 Python 3 not found. Installing..."
    case "${PKG_MANAGER}" in
        apt) run_as_root apt-get update && run_as_root apt-get install -y python3 ;;
        dnf) run_as_root dnf install -y python3 ;;
        pacman) run_as_root pacman -S --noconfirm python ;;
        zypper) run_as_root zypper install -y python3 ;;
        *) echo "⚠️ Could not identify the package manager to install python3." ;;
    esac
else
    echo "✅ Python 3 detectado: $(python3 --version)"
fi

# 5. Check and install Python Tkinter (required for GUI)
if ! python3 -c "import tkinter" >/dev/null 2>&1; then
    echo "📦 Graphical interface (Tkinter) not found. Installing python3-tk..."
    case "${PKG_MANAGER}" in
        apt) run_as_root apt-get update && run_as_root apt-get install -y python3-tk ;;
        dnf) run_as_root dnf install -y python3-tkinter ;;
        pacman) run_as_root pacman -S --noconfirm tk ;;
        zypper) run_as_root zypper install -y python3-tk ;;
        *) echo "⚠️ Install the Tkinter package manually for your distribution (ex: sudo apt install python3-tk)." ;;
    esac
else
    echo "✅ Tkinter (GUI) detectado e funcionando."
fi

# 6. Check and configure Node.js (multi-provider engine)
NODE_AVAILABLE=0
if command -v node >/dev/null 2>&1; then
    NODE_VER="$(node -v 2>/dev/null || echo '')"
    echo "✅ Node.js detectado no sistema: ${NODE_VER}"
    NODE_AVAILABLE=1
elif [ -x "${TARGET_DIR}/bin/node" ]; then
    echo "✅ Portable Node.js detected at ${TARGET_DIR}/bin/node"
    NODE_AVAILABLE=1
fi

if [ "${NODE_AVAILABLE}" -eq 0 ]; then
    echo ""
    echo "📦 Node.js was not found on this system."
    echo "⚡ Downloading portable Node.js v20 LTS directly into the AI Gauge folder..."
    echo "   (Zero system interference and no sudo password required!)"
    
    NODE_VERSION="v20.18.0"
    NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${ARCH}.tar.xz"
    TMP_DIR="$(mktemp -d)"
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${NODE_URL}" -o "${TMP_DIR}/node.tar.xz"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${TMP_DIR}/node.tar.xz" "${NODE_URL}"
    else
        echo "❌ curl or wget is required to download portable Node.js."
    fi

    if [ -f "${TMP_DIR}/node.tar.xz" ]; then
        tar -xJf "${TMP_DIR}/node.tar.xz" -C "${TARGET_DIR}/bin" --strip-components=2 "node-${NODE_VERSION}-linux-${ARCH}/bin/node" || true
        rm -rf "${TMP_DIR}"
        chmod +x "${TARGET_DIR}/bin/node"
        echo "✅ Portable Node.js v20 set up successfully at ${TARGET_DIR}/bin/node!"
    else
        echo "⚠️ Tentando instalar via gerenciador de pacotes do sistema..."
        case "${PKG_MANAGER}" in
            apt) run_as_root apt-get update && run_as_root apt-get install -y nodejs ;;
            dnf) run_as_root dnf install -y nodejs ;;
            pacman) run_as_root pacman -S --noconfirm nodejs ;;
            zypper) run_as_root zypper install -y nodejs ;;
        esac
    fi
fi

# 7. Scan de Provedores e Configuração Inicial
echo ""
echo "=========================================================="
echo " 🔍 Scanning for AI applications..."
echo "=========================================================="

CONFIG_DIR="${HOME}/.config/UniversalAIQuota"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "${CONFIG_DIR}"

HAS_ANTIGRAVITY=false
HAS_CLAUDE=false
HAS_CHATGPT=false
HAS_CURSOR=false
HAS_COPILOT=false
HAS_GEMINI=false

if pgrep -i antigravity >/dev/null 2>&1 || [ -d "$HOME/.gemini/antigravity" ]; then
    HAS_ANTIGRAVITY=true
fi

if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
    HAS_CLAUDE=true
fi

if [ -f "$HOME/.codex/auth.json" ] || [ -d "$HOME/.config/ChatGPT" ]; then
    HAS_CHATGPT=true
fi

if [ -d "$HOME/.config/Cursor" ] || [ -d "/opt/Cursor" ]; then
    HAS_CURSOR=true
fi

if [ -d "$HOME/.config/Code/User/globalStorage/github.copilot-chat" ] || command -v gh >/dev/null 2>&1; then
    HAS_COPILOT=true
fi

if [ -n "$GEMINI_API_KEY" ]; then
    HAS_GEMINI=true
elif [ -f "$CONFIG_FILE" ] && grep -A 3 '"gemini"' "$CONFIG_FILE" 2>/dev/null | grep -q '"api_key": "[^"]\+'; then
    HAS_GEMINI=true
fi

echo "  [1] ⚡ Antigravity:       $([ "$HAS_ANTIGRAVITY" = true ] && echo "✓ Detected on this system" || echo "○ Not detected (optional)")"
echo "  [2] 🟣 Claude (Pro/Code): $([ "$HAS_CLAUDE" = true ] && echo "✓ Session / Token detected" || echo "○ Not detected (optional)")"
echo "  [3] 🟢 ChatGPT (Desktop): $([ "$HAS_CHATGPT" = true ] && echo "✓ Desktop Session / Codex detected" || echo "○ Not detected (optional)")"
echo "  [4] 🔮 Cursor (IDE):      $([ "$HAS_CURSOR" = true ] && echo "✓ Detected on this system" || echo "○ Not detected (optional)")"
echo "  [5] 🔴 Copilot (VS Code): $([ "$HAS_COPILOT" = true ] && echo "✓ Detected (VS Code)" || echo "○ Not detected (optional)")"
echo "  [6] 🔷 Gemini (Studio):   $([ "$HAS_GEMINI" = true ] && echo "✓ Chave configurada" || echo "○ Chave de API (opcional)")"
echo ""

ENABLE_ANTI=true
ENABLE_CLAUDE=$HAS_CLAUDE
ENABLE_CHATGPT=$HAS_CHATGPT
ENABLE_CURSOR=$HAS_CURSOR
ENABLE_COPILOT=$HAS_COPILOT
ENABLE_GEMINI=$HAS_GEMINI

if [ -t 0 ] && { [ ! -f "$CONFIG_FILE" ] || [[ "$*" == *"--setup"* ]]; }; then
    echo "📋 Which quotas do you want to monitor in AI Gauge?"
    echo "   Press ENTER to monitor everything detected [Recommended],"
    echo "   or type the numbers you want, separated by commas (e.g. 1,2,3):"
    read -r -p "   Your choice [Default: Detected]: " USER_CHOICE
    
    if [ -n "$USER_CHOICE" ]; then
        ENABLE_ANTI=false
        ENABLE_CLAUDE=false
        ENABLE_CHATGPT=false
        ENABLE_CURSOR=false
        ENABLE_COPILOT=false
        ENABLE_GEMINI=false
        [[ "$USER_CHOICE" =~ 1 ]] && ENABLE_ANTI=true
        [[ "$USER_CHOICE" =~ 2 ]] && ENABLE_CLAUDE=true
        [[ "$USER_CHOICE" =~ 3 ]] && ENABLE_CHATGPT=true
        [[ "$USER_CHOICE" =~ 4 ]] && ENABLE_CURSOR=true
        [[ "$USER_CHOICE" =~ 5 ]] && ENABLE_COPILOT=true
        [[ "$USER_CHOICE" =~ 6 ]] && ENABLE_GEMINI=true
    fi
    echo ""
    echo "💡 Note: You can add or remove items at any time later in the app's settings."
    echo ""
fi

if [ ! -f "$CONFIG_FILE" ] || [[ "$*" == *"--setup"* ]]; then
    python3 -c "
import json, os
true, false = True, False
p = '$CONFIG_FILE'
cfg = {
    'providers': {
        'antigravity': {'enabled': $ENABLE_ANTI},
        'claude_pro': {'enabled': $ENABLE_CLAUDE},
        'chatgpt_subscription': {'enabled': $ENABLE_CHATGPT},
        'cursor': {'enabled': $ENABLE_CURSOR},
        'github_copilot': {'enabled': $ENABLE_COPILOT},
        'gemini': {'enabled': $ENABLE_GEMINI, 'api_key': os.environ.get('GEMINI_API_KEY', '')},
        'openai': {'enabled': False, 'api_key': ''},
        'anthropic': {'enabled': False, 'api_key': ''}
    },
    'refresh_interval_seconds': 30,
    'hidden_hud_gauges': [],
    'onboarding_completed': True
}
os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p, 'w') as f:
    json.dump(cfg, f, indent=2)
print('✅ Initial configuration saved to ~/.config/UniversalAIQuota/config.json!')
"
fi

# 8. Install AI Gauge application files
echo ""
echo "🚀 Installing AI Gauge files..."
cp -r "${REPO_DIR}/core" "${TARGET_DIR}/"
cp "${SCRIPT_DIR}/quota-hub.py" "${TARGET_DIR}/"
cp "${SCRIPT_DIR}/quota-hub" "${TARGET_DIR}/"
cp "${SCRIPT_DIR}/gemini-gauge" "${TARGET_DIR}/"

if [ -f "${SCRIPT_DIR}/icon.png" ]; then
    cp "${SCRIPT_DIR}/icon.png" "${TARGET_DIR}/icon.png"
    cp "${SCRIPT_DIR}/icon.png" "${ICON_DIR}/gemini-gauge.png"
elif [ -f "${REPO_DIR}/assets/icon.png" ]; then
    cp "${REPO_DIR}/assets/icon.png" "${TARGET_DIR}/icon.png"
    cp "${REPO_DIR}/assets/icon.png" "${ICON_DIR}/gemini-gauge.png"
fi

chmod +x "${TARGET_DIR}/quota-hub" "${TARGET_DIR}/gemini-gauge" "${TARGET_DIR}/quota-hub.py"

# Write direct launcher wrappers into ~/.local/bin
cat << 'LAUNCHER_EOF' > "${BIN_DIR}/gemini-gauge"
#!/usr/bin/env bash
TARGET_DIR="${HOME}/.local/share/universal-ai-quota"
if [ -f "${TARGET_DIR}/quota-hub.py" ]; then
    exec python3 "${TARGET_DIR}/quota-hub.py" "$@"
fi

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
exec python3 "${SCRIPT_DIR}/quota-hub.py" "$@"
LAUNCHER_EOF

chmod +x "${BIN_DIR}/gemini-gauge"
cp "${BIN_DIR}/gemini-gauge" "${BIN_DIR}/quota-hub"

# Also symlink to /usr/local/bin if writable or sudo available for global access
if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
    ln -sf "${BIN_DIR}/gemini-gauge" "/usr/local/bin/gemini-gauge" 2>/dev/null || true
    ln -sf "${BIN_DIR}/gemini-gauge" "/usr/local/bin/quota-hub" 2>/dev/null || true
elif command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
    sudo ln -sf "${BIN_DIR}/gemini-gauge" "/usr/local/bin/gemini-gauge" 2>/dev/null || true
    sudo ln -sf "${BIN_DIR}/gemini-gauge" "/usr/local/bin/quota-hub" 2>/dev/null || true
fi

# Ensure ~/.local/bin is in PATH for bash and zsh
if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    if [ -f "${HOME}/.bashrc" ] && ! grep -q '\.local/bin' "${HOME}/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${HOME}/.bashrc"
    fi
    if [ -f "${HOME}/.zshrc" ] && ! grep -q '\.local/bin' "${HOME}/.zshrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${HOME}/.zshrc"
    fi
fi

# Desktop launcher entry
sed -e "s|^Exec=.*|Exec=${BIN_DIR}/gemini-gauge|" \
    -e "s|^Icon=.*|Icon=${TARGET_DIR}/icon.png|" \
    "${SCRIPT_DIR}/quota-hub.desktop" > "${APP_DIR}/gemini-gauge.desktop"
chmod +x "${APP_DIR}/gemini-gauge.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APP_DIR}" || true
fi

echo ""
echo "=========================================================="
echo " 🎉 Installation completed successfully!"
echo "=========================================================="
echo "👉 To open the graphical interface:"
echo "   - Type in a terminal: gemini-gauge (or quota-hub)"
echo "   - Or click the 'AI Gauge' icon in your Linux applications menu"
echo ""
echo "👉 To see the quotas directly in the terminal (text mode / SSH):"
echo "   gemini-gauge --cli"
echo "=========================================================="
echo ""
