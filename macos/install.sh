#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=========================================================="
echo " ⚡ AI Gauge - Monitor Inteligente de Quotas (macOS)"
echo " Developed by VH2C • https://vh2c.com.br"
echo "=========================================================="
echo ""

# ----------------------------------------------------
# 1. SCAN DE APLICATIVOS DE IA INSTALADOS
# ----------------------------------------------------
echo "🔍 Escaneando aplicativos e sessões de IA no computador..."

CONFIG_DIR="${HOME}/.config/UniversalAIQuota"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "${CONFIG_DIR}"

HAS_ANTIGRAVITY=false
HAS_CLAUDE=false
HAS_CHATGPT=false
HAS_CURSOR=false
HAS_COPILOT=false
HAS_GEMINI=false

# Antigravity (App, process, or local config)
if pgrep -i Antigravity >/dev/null 2>&1 || [ -d "/Applications/Antigravity.app" ] || [ -d "$HOME/.gemini/antigravity" ]; then
    HAS_ANTIGRAVITY=true
fi

# Claude (Keychain session, ~/.claude, /Applications/Claude.app, or claude CLI)
if /usr/bin/security find-generic-password -a "$USER" -s "Claude Code-credentials" >/dev/null 2>&1 || [ -d "$HOME/.claude" ] || [ -d "/Applications/Claude.app" ] || command -v claude >/dev/null 2>&1; then
    HAS_CLAUDE=true
fi

# ChatGPT (Desktop ~/.codex/auth.json, Keychain, or /Applications/ChatGPT.app)
if [ -f "$HOME/.codex/auth.json" ] || /usr/bin/security find-generic-password -a "$USER" -s "ChatGPT-credentials" >/dev/null 2>&1 || [ -d "/Applications/ChatGPT.app" ]; then
    HAS_CHATGPT=true
fi

# Cursor (App, support directory, or running process)
if [ -d "/Applications/Cursor.app" ] || [ -d "$HOME/Library/Application Support/Cursor" ] || pgrep -i Cursor >/dev/null 2>&1; then
    HAS_CURSOR=true
fi

# GitHub Copilot (Visual Studio Code or Copilot storage)
if [ -d "/Applications/Visual Studio Code.app" ] || [ -d "$HOME/Library/Application Support/Code/User/globalStorage/github.copilot-chat" ] || command -v gh >/dev/null 2>&1; then
    HAS_COPILOT=true
fi

# Gemini (API Key configured in environment or existing config)
if [ -n "$GEMINI_API_KEY" ]; then
    HAS_GEMINI=true
elif [ -f "$CONFIG_FILE" ] && grep -A 3 '"gemini"' "$CONFIG_FILE" 2>/dev/null | grep -q '"api_key": "[^"]\+'; then
    HAS_GEMINI=true
fi

echo "  [1] ⚡ Antigravity:       $([ "$HAS_ANTIGRAVITY" = true ] && echo "✓ Detectado no Mac" || echo "○ Não detectado (opcional)")"
echo "  [2] 🟣 Claude (Pro/Code): $([ "$HAS_CLAUDE" = true ] && echo "✓ Sessão / Token detectado" || echo "○ Não detectado (opcional)")"
echo "  [3] 🟢 ChatGPT (Desktop): $([ "$HAS_CHATGPT" = true ] && echo "✓ Sessão Desktop / Codex detectada" || echo "○ Não detectado (opcional)")"
echo "  [4] 🔮 Cursor (IDE):      $([ "$HAS_CURSOR" = true ] && echo "✓ Detectado no Mac" || echo "○ Não detectado (opcional)")"
echo "  [5] 🔴 Copilot (VS Code): $([ "$HAS_COPILOT" = true ] && echo "✓ Detectado no Mac (VS Code)" || echo "○ Não detectado (opcional)")"
echo "  [6] 🔷 Gemini (Studio):   $([ "$HAS_GEMINI" = true ] && echo "✓ Chave configurada" || echo "○ Chave de API (opcional)")"
echo ""

# ----------------------------------------------------
# 2. PERGUNTA INICIAL AO USUÁRIO
# ----------------------------------------------------
ENABLE_ANTI=true
ENABLE_CLAUDE=$HAS_CLAUDE
ENABLE_CHATGPT=$HAS_CHATGPT
ENABLE_CURSOR=$HAS_CURSOR
ENABLE_COPILOT=$HAS_COPILOT
ENABLE_GEMINI=$HAS_GEMINI

if [ -t 0 ] && { [ ! -f "$CONFIG_FILE" ] || [[ "$*" == *"--setup"* ]]; }; then
    echo "📋 Quais quotas você deseja monitorar no seu AI Gauge?"
    echo "   Pressione ENTER para monitorar todos os detectados [Recomendado],"
    echo "   ou digite os números desejados separados por vírgula (ex: 1,2,3):"
    read -r -p "   Sua escolha [Padrão: Detectados]: " USER_CHOICE
    
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
    echo "💡 Informação: Você poderá adicionar ou excluir itens a qualquer momento depois nas Configurações (⌘,) do app."
    echo ""
fi

# Gravar config inicial caso não exista ou se solicitado
if [ ! -f "$CONFIG_FILE" ] || [[ "$*" == *"--setup"* ]]; then
    python3 -c "
import json, os
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
print('✅ Configuração inicial gravada com sucesso em ~/.config/UniversalAIQuota/config.json!')
"
fi

# ----------------------------------------------------
# 3. COMPILAÇÃO E INSTALAÇÃO
# ----------------------------------------------------
echo "⚡ Compilando o AI Gauge para macOS..."
"${SCRIPT_DIR}/build.sh"

echo "📲 Instalando em /Applications..."
rm -rf "/Applications/Gemini Gauge.app" 2>/dev/null || true
rm -rf "/Applications/AI Gauge.app" 2>/dev/null || true
cp -R "${SCRIPT_DIR}/AI Gauge.app" /Applications/

# Clear quarantine bit
xattr -cr "/Applications/AI Gauge.app" 2>/dev/null || true

# Package ZIP for Downloads and Releases
mkdir -p "${REPO_DIR}/dist" "${HOME}/Downloads"
(cd "${SCRIPT_DIR}" && zip -r -y "${REPO_DIR}/dist/AI-Gauge-macOS-vh2c.zip" "AI Gauge.app")
cp "${REPO_DIR}/dist/AI-Gauge-macOS-vh2c.zip" "${HOME}/Downloads/"

echo ""
echo "=========================================================="
echo " 🎉 AI Gauge instalado e pré-configurado com sucesso!"
echo " 📍 Aplicativo: /Applications/AI Gauge.app"
echo " 📦 Arquivo ZIP copiado para: ~/Downloads/AI-Gauge-macOS-vh2c.zip"
echo " 💡 Dica: Você pode abrir com 'open \"/Applications/AI Gauge.app\"'"
echo "    e gerenciar as quotas a qualquer momento em Preferências (⌘,)."
echo "=========================================================="
