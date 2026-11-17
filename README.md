<div align="center">

# ⚡ AI Gauge

### Multi-Platform AI Quota & Rate Limit Cockpit for macOS, Linux & Windows
**Developed by [VH2C](https://vh2c.com.br)**

[![Total Downloads](https://img.shields.io/github/downloads/vh2c/gemini-gauge/total.svg?style=flat-square&logo=github&color=00E699)](https://github.com/vh2c/gemini-gauge/releases)
[![Latest Release](https://img.shields.io/github/v/release/vh2c/gemini-gauge?style=flat-square&color=38BDF8)](https://github.com/vh2c/gemini-gauge/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey.svg?style=flat-square)](#)
[![Powered by VH2C](https://img.shields.io/badge/Developed%20by-vh2c.com.br-00C9FF?style=flat-square)](https://vh2c.com.br)

<br/>

<img src="assets/icon_1024.png" width="180" height="180" alt="AI Gauge Icon" />

<br/>

**AI Gauge** é um cockpit leve e de alto desempenho para monitorar em tempo real as cotas, limites de taxa (RPM/TPM) e janelas de renovação dos seus modelos de inteligência artificial no macOS, Linux e Windows. Funciona de forma **totalmente independente de IDEs**, agregando em um único painel **Antigravity**, **Claude**, **ChatGPT**, **Cursor**, **GitHub Copilot (VS Code)** e **Gemini**.

> 💡 **Detecção Zero-Config (Plug & Play)**: Se você já utiliza os aplicativos no seu computador, o AI Gauge detecta as sessões locais de forma 100% automática. Não é necessário digitar tokens nem senhas para o **Antigravity**, **Claude**, **ChatGPT**, **Cursor** ou **Copilot**!

</div>

---

## 📦 Downloads Prontos para Uso (v1.1)

Para testadores e usuários leigos: **não é necessário compilar código**. Basta baixar o pacote correspondente ao seu sistema operacional:

| Plataforma | Pacote (.zip / .tar.gz) | Tamanho | Como Instalar |
| :--- | :--- | :---: | :--- |
| 🍏 **macOS** | [**AI-Gauge-macOS-vh2c.zip**](releases/v1.1/AI-Gauge-macOS-vh2c.zip?raw=true) | `2.5 MB` | Extraia e arraste o **AI Gauge.app** para a pasta `/Applications`, ou execute `./install.sh`. |
| 🪟 **Windows** | [**AI-Gauge-Windows-vh2c.zip**](releases/v1.1/AI-Gauge-Windows-vh2c.zip?raw=true) | `0.2 MB` | Extraia o ZIP e dê dois cliques em **`install.bat`**. O Node.js portátil é baixado automaticamente. |
| 🐧 **Linux** | [**AI-Gauge-Linux-vh2c.tar.gz**](releases/v1.1/AI-Gauge-Linux-vh2c.tar.gz?raw=true) | `5.9 MB` | Extraia o arquivo e execute **`./install.sh`** no terminal. |

---

## 🌟 Principais Recursos e Seções do HUD

As informações no HUD lateral flutuante são agrupadas por aplicativo/provedor com cores de destaque exclusivas:

1. **`Antigravity`** *(Azul Pastel `#8FBCFF` - IDE Dedicado)*:
   - Monitoramento direto do ecossistema do **Google Antigravity IDE** (ao vivo ou headless).
   - **Gemini**: Cotas semanal e janela de 5 horas.
   - **Claude/GPT**: Cota interna de terceiros (Opus 5.5, Sonnet 5.5, GPT-OSS 120B).
   - **Argon**: Cota semanal dedicada para Gemini 4 Argon WTU.
   - *Autenticação:* **Zero-Config** (lê diretamente do processo/ambiente do IDE).

2. **`Claude`** *(Coral Terracota `#D78C68` - App Desktop Anthropic)*:
   - Monitora sua conta e assinatura oficial Claude (Pro / Team).
   - **5 Hours Limit**: Janela rotativa de 5 horas da sessão atual.
   - **Weekly Limit**: Cota semanal com contagem regressiva para renovação.
   - *Autenticação:* **Zero-Config** (captura do macOS Keychain com auto-renovação de token expirado).

3. **`ChatGPT`** *(Verde Menta `#8AE39A` - App Desktop OpenAI)*:
   - Monitora seu acesso à conta oficial do ChatGPT (Free, Plus, Pro, Team).
   - **GPT-4o (3h / Cota Ativa)**: Janela de mensagens e limite de taxa.
   - **o1 Reasoning (Semanal)**: Cota semanal para modelos com raciocínio avançado.
   - *Autenticação:* **Zero-Config** (detecta automaticamente a sessão do app em `~/.codex/auth.json`).

4. **`Cursor`** *(Roxo Neon `#A855F7` - Cursor IDE)*:
   - Monitora as cotas da sua assinatura Cursor (Pro / Business / Fast Requests).
   - **Fast Requests**: Cota mensal de requisições rápidas de modelos premium (Claude 3.5 Sonnet & GPT-4o).
   - **Ciclo Mensal**: Contagem regressiva até a renovação da cota da fatura mensal.
   - *Autenticação:* **Zero-Config** (extração automática do armazenamento local do Cursor em `state.vscdb`).

5. **`Copilot`** *(Coral Vibrante `#FF5265` - Visual Studio Code)*:
   - Monitora o status e limites do **Copilot** no VS Code.
   - **Copilot Chat & Model Limits**: Cota de mensagens de chat e acesso a Claude 3.5 Sonnet / GPT-4o.
   - **Completions Rate Limits**: Limites de taxa de geração de código em tempo real.
   - *Autenticação:* **Zero-Config** (detecta o ambiente do VS Code, tokens da CLI `gh` ou credenciais locais).

6. **`Gemini`** *(Branco/Prata `#EBEBEB` - API Google AI Studio)*:
   - Monitoramento das chaves de API diretas de desenvolvedor.
   - **Flash RPM & Pro RPM**: Limites de requisições por minuto e status de chave.
   - *Autenticação:* Requer preenchimento da chave de API (`AIzaSy...`) obtida no [Google AI Studio](https://aistudio.google.com).

---

## 🧙‍♂️ Assistente de Boas-Vindas & Auto-Scan (Onboarding Wizard)

Ao instalar ou iniciar o **AI Gauge** pela primeira vez, o assistente inteligente faz uma varredura automática do seu sistema:
* **Scan de Provedores:** Identifica se **Antigravity**, **Claude** (Claude Code/Keychain) e **ChatGPT** (sessão Desktop) já estão presentes na sua máquina.
* **Seleção Inicial Intuitiva:** Apresenta uma janela elegante de configuração rápida perguntando quais quotas você deseja monitorar no seu Cockpit.
* **Flexibilidade Total:** Você pode marcar ou desmarcar provedores a qualquer momento posteriormente através de **Configurações (⌘,)** ou pelo ícone da barra de status.
* **Modo Terminal / CLI:** Os scripts de instalação (`install.sh` / `install.ps1`) também incluem o assistente interativo no terminal!

---

## 🔋 Como Ler os Marcadores (Escala de Combustível)

Todos os relógios (gauges analógicos) do AI GAUGE operam como um **marcador de bateria ou combustível**:
* **100%** = Tanque cheio / Cota totalmente disponível.
* **0%** = Cota esgotada.

> ℹ️ **Diferença para telas oficiais (como Claude.ai):**
> Aplicativos como o Claude expressam o consumo em **% USADA** (*ex: "5% used"*).
> No AI GAUGE, isso equivale a **95% DISPONÍVEL**.

* **Verde (`#00E699`)**: Cota Saudável (50% – 100% restante).
* **Âmbar (`#F5A623`)**: Uso Moderado (20% – 49% restante).
* **Vermelho (`#FF4D4F`)**: Alerta de Cota Baixa (< 20% restante).

---

## ⌨️ Atalhos Rápidos

| Atalho | Ação |
| :--- | :--- |
| `Cmd + M` (Mac) / `Ctrl + M` (Linux/Win) | Alternar entre **Janela Completa** e **HUD Flutuante** |
| `Cmd + O` (Mac) / `Ctrl + O` (Linux/Win) | Alternar orientação do HUD (**Vertical** / **Horizontal**) |
| `Cmd + R` (Mac) / `Ctrl + R` (Linux/Win) | Atualizar todas as métricas imediatamente |
| `Cmd + ,` (Mac) / `Ctrl + ,` (Linux/Win) | Abrir tela de **Configurações (⚙️)** |
| `Cmd + W` / `Esc` | Ocultar ou fechar janela |

---

## 🚀 Instalação Rápida

### 🍏 macOS (Apple Silicon & Intel)
1. Baixe o pacote: [**AI-Gauge-macOS-vh2c.zip**](releases/v1.1/AI-Gauge-macOS-vh2c.zip?raw=true)
2. Extraia o ZIP e mova o **`AI Gauge.app`** para a pasta `/Applications` (ou rode `./install.sh`).
3. Abra o `AI Gauge` pelo Spotlight ou Launchpad.

*Ou compile diretamente do código:*
```bash
git clone https://github.com/vh2c/gemini-gauge.git
cd gemini-gauge/ai_gauge_app/macos
./install.sh
```

---

### 🐧 Linux (Ubuntu, Debian, Fedora, Arch, Mint)
1. Baixe o pacote: [**AI-Gauge-Linux-vh2c.tar.gz**](releases/v1.1/AI-Gauge-Linux-vh2c.tar.gz?raw=true)
2. Extraia o arquivo e execute o script autossuficiente:
```bash
tar -xzf AI-Gauge-Linux-vh2c.tar.gz
cd AI-Gauge-Linux
./install.sh
```

---

### 🪟 Windows (Windows 10 / 11)
**Opção recomendada (1 clique):** baixe **`AI-Gauge-Setup.exe`** na página de [Releases](https://github.com/vh2c/gemini-gauge/releases/latest) e execute. Já inclui o Node.js, não pede administrador, cria os atalhos e substitui versões anteriores.

**Opção alternativa (ZIP):**
1. Baixe o pacote: [**AI-Gauge-Windows-vh2c.zip**](releases/v1.1/AI-Gauge-Windows-vh2c.zip?raw=true)
2. Extraia o ZIP (não execute de dentro do ZIP).
3. Dê dois cliques em **`install.bat`**. Não precisa de administrador nem de Node.js instalado: se faltar, o instalador baixa um Node.js portátil (~30 MB, uma única vez, com verificação SHA-256).
4. Os atalhos são criados na Área de Trabalho e no Menu Iniciar. Uma versão anterior é removida automaticamente e suas configurações são mantidas.
5. Para desinstalar: **Configurações → Aplicativos** (ou Menu Iniciar → *Desinstalar AI Gauge*).

---

## 📊 Telemetria & Privacidade

O AI Gauge envia apenas pings anônimos para verificação de novas versões, avisos e contagem global de usuários:
- **Quando**: um ping de inicialização (no máximo a cada 6 horas) e, no máximo uma vez por hora, uma consulta de avisos/versão que não conta como nova abertura.
- **O que é enviado**: Hash anônimo de máquina (`machine_id`), sistema operacional (`macOS`/`Linux`/`Windows`), arquitetura e versão do aplicativo.
- **Como desligar**: defina `"telemetry": false` no `config.json` (sem telemetria, os avisos também deixam de ser recebidos).
- **O que NUNCA é enviado**: Nenhuma chave de API, prompt, token, código, projeto ou dado pessoal.

---

## 💼 Soluções de IA sob Medida para Empresas

Precisa de agentes autônomos de IA, orquestração de workflows complexos ou desenvolvimento sob medida para sua organização?

Conheça a **[VH2C](https://vh2c.com.br)** ou fale com nossa equipe de engenharia.

---

## 📄 Licença

Distribuído sob a licença **MIT**. Veja o arquivo `LICENSE` para mais informações.  
Desenvolvido com ⚡ por **[VH2C](https://vh2c.com.br)**.
