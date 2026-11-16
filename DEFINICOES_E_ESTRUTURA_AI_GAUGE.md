# AI GAUGE — DEFINIÇÕES DE ARQUITETURA, ESTRUTURA E BANCO DE DADOS
> **Documento Oficial de Planejamento e Especificação Técnica**  
> **Ecossistema:** VH2C • `https://vh2c.com.br`  
> **Diretório do Projeto:** `/Volumes/ED01/AntiGravity/ai_gauge`  
> **Data:** 14/11/2026

---

## 1. Visão Geral e Transição de Nome ('AI GAUGE')

O projeto evoluiu de um monitor focado em Gemini para um cockpit universal de cotas e limites de inteligência artificial em tempo real (Antigravity IDE, Claude Code/Pro, ChatGPT Plus/Pro, Google AI Studio, OpenAI API e Anthropic API).

* **Nome Oficial do Produto:** `AI GAUGE` (antigo *Gemini Gauge / Quota Hub*).
* **Slogan:** *Universal AI Quota & Limits Cockpit for Developers*.
* **Identidade Visual e Seções do HUD:** Fundo escuro (`#121212` / `#181818`), acentos temáticos por provedor:
  - **Antigravity (IDE Dedicado):** Azul suave / pastel (`#8FBCFF`) - Gemini, Claude/GPT e Argon.
  - **Claude (Sessão Desktop):** Coral/Terracota (`#D78C68`) - Janela de 5h e cota semanal.
  - **ChatGPT (Sessão Desktop):** Verde OpenAI (`#10A37F`) - Janela de 3h e cota semanal o1.
  - **Gemini (API):** Off-White / Prata (`#EBEBEB`) - Chave de API Google AI Studio.
  - **Status Saudável / HUD:** Verde suave (`#00E699` / `#8AE39A`).
  - **Alerta / Crítico:** Âmbar (`#F5A623`) e Vermelho (`#FF4D4F`).

### 1.1 Autenticação Zero-Config (Plug & Play) e Escala de Leitura
* **Antigravity:** 100% automático (inspeção de processos e sockets do IDE local).
* **Claude:** 100% automático (leitura do macOS Keychain `Claude Code-credentials` com auto-renovação de tokens expirados).
* **ChatGPT:** 100% automático (leitura da sessão ativa do app desktop macOS em `~/.codex/auth.json` com cabeçalho `ChatGPT-Account-ID`).
* **Gemini (API):** Preenchimento manual da chave de API (`AIzaSy...`).
* **Escala dos Relógios:** Modo tacômetro/marcador de combustível (100% = tanque cheio / cota restante, 0% = esgotado). Inverte a lógica de exibição de apps que mostram % consumida para garantir leitura intuitiva de disponibilidade.

### 1.2 Assistente de Boas-Vindas & Auto-Scan (Onboarding Wizard)
* **Scan Automático de Provedores:** Na primeira execução ou instalação, o sistema faz uma varredura automática nos serviços instalados (Antigravity, Claude, ChatGPT, Gemini).
* **Seleção de Quotas Inicial:** Interface gráfica (AppKit no Mac) ou terminal interativo (Linux/Windows) questiona ao usuário quais serviços ele deseja monitorar no seu Cockpit.
* **Pre-configuração Transparente:** Grava imediatamente `~/.config/UniversalAIQuota/config.json` e marca `onboarding_completed: true`, deixando o app 100% funcional sem exigir setup posterior.
* **Flexibilidade Total:** O usuário é informado de que pode adicionar, excluir ou ocultar gauges específicos a qualquer momento no menu de **Configurações (⌘,)**.

---

## 2. Estrutura de Diretórios no Repositório Central

Seguindo rigorosamente a skill `desenvolvimento`, a raiz do projeto em `/Volumes/ED01/AntiGravity/ai_gauge` conterá as aplicações divididas por responsabilidade:

```text
/Volumes/ED01/AntiGravity/ai_gauge/
├── ai_gauge_app/             # Aplicativo desktop cliente (macOS, Windows, Linux)
│   ├── core/                 # Motor Node.js de captura de cotas e telemetria
│   ├── macos/                # App Swift nativo (HUD Flutuante, Tacômetros, Dock)
│   ├── windows/              # App PowerShell + WPF + VBS launcher
│   ├── linux/                # App Python + Tkinter/Canvas
│   └── dist/                 # Pacotes ZIP/tar.gz para download
├── ai_gauge_api/             # Backend REST em PHP 8.2.35-apache + PostgreSQL
│   ├── docker-compose.yml    # Configuração do serviço na VPS (redes database_network e npm_network)
│   ├── Dockerfile            # Base segura php:8.2.35-apache + Apache Security Hardening
│   ├── src/
│   │   ├── config/           # Conexão DB centralizado (sem .env em produção)
│   │   ├── core/             # CoreService, DBService, RouterService, AuthService
│   │   ├── controllers/      # TelemetryController, LicenseController, AdminController
│   │   └── index.php         # Roteador central REST
│   └── cron/                 # Robôs de limpeza periódica da base
├── ai_gauge_landpage/        # Landing page institucional e de conversão
│   ├── index.html            # LP de vendas com tabela Free vs Pro e download
│   ├── download/             # Página com detecção automática de OS
│   ├── sintese.md            # Documentação de referência para agentes de IA
│   └── assets/               # SVGs, ícones, CSS e imagens
├── releases/                 # Binários e arquivos compactados das versões públicas
└── DEFINICOES_E_ESTRUTURA_AI_GAUGE.md
```

---

## 3. Base de Dados PostgreSQL (Centralizada na VPS)

Conforme a skill `base_de_dados`, o banco será criado no container centralizado `postgres` da VPS VH2C com o nome **`ai_gauge`**.

### 3.1 Diretrizes e Convenções:
1. **Nomenclatura:** Padrão `snake_case` descritivo sem abreviações desnecessárias.
2. **Chaves Primárias (Prevenção IDOR):** `UUID DEFAULT gen_random_uuid()`.
3. **Auditoria Obrigatória:** `created_at timestamptz DEFAULT now()`, `updated_at timestamptz DEFAULT now()`, e soft delete com `deleted_at timestamptz NULL`.
4. **Trigger de Atualização Automática:** Trigger global para atualizar `updated_at`.
5. **Segurança:** Senhas criptografadas em bcrypt, controle de tokens com expiração e bloqueio de IPs maliciosos.

---

### 3.2 Script DDL Completo (PostgreSQL)

```sql
-- Habilita extensão para geração de UUIDv4
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Função trigger para atualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 1. TABELA DE USUÁRIOS (Administradores e Gestores)
CREATE TABLE IF NOT EXISTS usuarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome VARCHAR(150) NOT NULL,
    email VARCHAR(180) UNIQUE NOT NULL,
    senha VARCHAR(255) NOT NULL,
    nivel_acesso VARCHAR(50) DEFAULT 'admin',
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);

CREATE TRIGGER set_timestamp_usuarios
BEFORE UPDATE ON usuarios
FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();

-- 2. TABELA DE TOKENS DE AUTENTICAÇÃO
CREATE TABLE IF NOT EXISTS tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    token VARCHAR(255) UNIQUE NOT NULL,
    tipo VARCHAR(50) DEFAULT 'bearer', -- 'browser' (30 dias) ou 'api' (auto-renovavel)
    origem VARCHAR(100) NULL,
    expira_em TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);

-- 3. TABELA DE IPS BLOQUEADOS (Defesa contra Brute Force / Abuso)
-- Regra da skill: 1º bloqueio por 10 minutos, 2º bloqueio por 24 horas
CREATE TABLE IF NOT EXISTS ips_bloqueados (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ip_address VARCHAR(45) NOT NULL,
    motivo VARCHAR(255) NOT NULL,
    tentativas INT DEFAULT 1,
    nivel_bloqueio INT DEFAULT 1, -- 1: 10 minutos, 2: 24 horas
    bloqueado_ate TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);
CREATE INDEX idx_ips_bloqueados_ip ON ips_bloqueados(ip_address, bloqueado_ate);

-- 4. TABELA DE PARÂMETROS PARA LIMPEZA PERIÓDICA (CRON)
CREATE TABLE IF NOT EXISTS parametros_limpeza (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome_tabela VARCHAR(100) NOT NULL,
    regra_sql TEXT NOT NULL,
    dias_retencao INT DEFAULT 30,
    ativo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. TABELA DE LICENÇAS (Free vs Pro)
CREATE TABLE IF NOT EXISTS licencas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chave_licenca VARCHAR(64) UNIQUE NOT NULL, -- Ex: AG-PRO-XXXX-XXXX-XXXX
    cliente_email VARCHAR(180) NOT NULL,
    cliente_nome VARCHAR(150) NULL,
    plano VARCHAR(50) DEFAULT 'pro',           -- 'free', 'pro', 'enterprise'
    status VARCHAR(50) DEFAULT 'ativa',        -- 'ativa', 'suspensa', 'expirada'
    max_dispositivos INT DEFAULT 2,
    data_inicio TIMESTAMPTZ DEFAULT now(),
    data_expiracao TIMESTAMPTZ NULL,           -- NULL para vitalício / assinatura contínua
    pais_origem VARCHAR(3) NULL,               -- ISO alpha-2/3 (ex: BRA, USA)
    notas TEXT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);
CREATE INDEX idx_licencas_chave ON licencas(chave_licenca);
CREATE INDEX idx_licencas_email ON licencas(cliente_email);

-- 6. TABELA DE DISPOSITIVOS / MÁQUINAS INSTALADAS (Telemetria)
CREATE TABLE IF NOT EXISTS dispositivos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    licenca_id UUID NULL REFERENCES licencas(id) ON DELETE SET NULL,
    machine_id VARCHAR(120) NOT NULL,
    plataforma VARCHAR(50) NOT NULL,          -- 'darwin', 'win32', 'linux'
    versao_app VARCHAR(50) NOT NULL,          -- '1.1.0'
    pais VARCHAR(3) DEFAULT 'BRA',            -- Detectado via GeoIP (ex: BR, US, DE)
    ip_hash VARCHAR(64) NULL,                 -- Anonimizado LGPD (hash diário)
    ultimo_heartbeat TIMESTAMPTZ DEFAULT now(),
    total_aberturas INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT unq_dispositivo_machine UNIQUE (machine_id)
);
CREATE INDEX idx_dispositivos_pais ON dispositivos(pais);
CREATE INDEX idx_dispositivos_heartbeat ON dispositivos(ultimo_heartbeat);

-- 7. TABELA DE MENSAGENS E ANÚNCIOS REMOTOS (Broadcast no App)
CREATE TABLE IF NOT EXISTS mensagens_globais (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    titulo VARCHAR(120) NOT NULL,
    mensagem TEXT NOT NULL,
    badge VARCHAR(30) DEFAULT 'AVISO',        -- 'NOVIDADE', 'PRO', 'MANUTENÇÃO'
    tipo VARCHAR(30) DEFAULT 'info',           -- 'info', 'promo', 'warning'
    action_label VARCHAR(60) NULL,             -- 'Assinar Pro', 'Ver Documentação'
    action_url VARCHAR(255) NULL,
    versao_minima VARCHAR(30) NULL,
    ativo BOOLEAN DEFAULT true,
    data_inicio TIMESTAMPTZ DEFAULT now(),
    data_fim TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);

-- 8. TABELA DE TELEMETRIA DA LANDING PAGE (Funil de Conversão)
CREATE TABLE IF NOT EXISTS landpage_visitas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pagina VARCHAR(60) NOT NULL,               -- 'lp_principal', 'lp_download', 'checkout'
    origem VARCHAR(255) NULL,                  -- 'google', 'direto', referer
    url_completa TEXT NULL,
    pais VARCHAR(3) NULL,
    ip_hash VARCHAR(64) NULL,
    user_agent TEXT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_landpage_pagina ON landpage_visitas(pagina, created_at);
```

---

## 4. Arquitetura da API REST (`ai_gauge_api`)

Em consonância com a skill `api`, a estrutura de classes respeitará os 5 blocos padronizados da VH2C:

1. **`CoreService`**:
   - `encrypt()` / `decrypt()` com chaves seguras do container.
   - `format_date()` e manipulação de timezone.
   - `check_json()` e validação de payloads.
   - Bloqueio e verificação de IPs (`check_ip_block()`, `block_ip()`, `unblock_ip()`).
2. **`DBService`**:
   - Centraliza conexão PDO com o PostgreSQL na rede `database_network`.
   - Métodos `search()`, `create()`, `update()`, `soft_delete()`, `numrows()` e `json_result()`.
3. **`AuthService`**:
   - Validação de Bearer tokens.
   - Regras de expiração (30 dias para painel web; renovação contínua para chamadas do app desktop).
4. **`RouterService`**:
   - Roteador REST simples e performático (`get()`, `post()`, `put()`, `delete()`).
5. **`ApiService` (Controladores)**:
   - `TelemetryController@heartbeat`: Recebe ping do app, atualiza `dispositivos`, resolve GeoIP e devolve announcements ativos e status de update.
   - `LicenseController@validate`: Valida a chave de licença enviada pelo app.
   - `AnnouncementController@list`: Retorna os avisos vigentes para renderizar o banner no app.
   - `VisitorController@track`: Endpoint `sendBeacon` / `fetch` para métricas da landing page.
   - `AdminController`: Métricas agregadas de licenças e dispositivos distribuídos por país para o painel de controle.

---

## 5. Interface de Gestão (Estilo `licencas.digitalparking.com.br`)

O painel administrativo permitirá gerenciar o ciclo de vida do AI Gauge:
1. **Mapa de Licenças e Usuários por País:** Gráfico/tabela destacando quantidade de máquinas ativas por país (Brasil, EUA, Europa, etc.) via GeoIP.
2. **Gerenciador de Mensagens Globais:** Criação e desativação em tempo real dos banners que aparecem no topo do app macOS/Windows/Linux (sem necessidade de nova versão).
3. **Gestão de Licenças Pro:** Emissão de chaves, revogação e visualização das máquinas vinculadas.
4. **Funil de Conversão da Landpage:** Visitas na LP ➔ Downloads realizados ➔ Instalações ativas ➔ Licenças ativadas.

---

## 6. Dockerfile e Docker Compose para VPS (Deploy DigitalOcean)

### `Dockerfile`
```dockerfile
FROM php:8.2.35-apache

RUN apt-get update && apt-get install -y \
    libpq-dev \
    libzip-dev \
    zip \
    unzip \
    && docker-php-ext-install pdo pdo_pgsql pgsql \
    && rm -rf /var/lib/apt/lists/*

RUN a2enmod rewrite headers

# Hardening obrigatório do Apache VH2C
COPY docker/apache-security.conf /etc/apache2/conf-available/security-vh2c.conf
RUN a2enconf security-vh2c

WORKDIR /var/www/html
COPY src/ /var/www/html/
RUN chown -R www-data:www-data /var/www/html
```

### `docker-compose.yml`
```yaml
version: '3.8'

services:
  ai_gauge_api:
    build: .
    container_name: ai-gauge-api
    restart: unless-stopped
    networks:
      - database_network
      - npm_network
    environment:
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_NAME=ai_gauge
      - DB_USER=postgres
      - DB_PASS=${POSTGRES_ROOT_PASSWORD}
      - APP_ENV=production
      - TZ=America/Sao_Paulo

networks:
  database_network:
    external: true
  npm_network:
    external: true
```

---

## 7. Próximos Passos Imediatos para Amanhã

1. **Renomeação nos Aplicativos:**
   - Atualizar a identidade visual e strings de `Gemini Gauge` para `AI Gauge` em `macos/`, `linux/` e `windows/`.
2. **Criação da Base e API:**
   - Criar banco `ai_gauge` no PostgreSQL central da VPS e rodar o script DDL acima.
   - Estruturar a pasta `/Volumes/ED01/AntiGravity/ai_gauge/ai_gauge_api` com o roteador e endpoints de telemetria e licença.
3. **Landing Page:**
   - Iniciar `/Volumes/ED01/AntiGravity/ai_gauge/ai_gauge_landpage` com o design de alta conversão, chatbot n8n e contador de visitas.
