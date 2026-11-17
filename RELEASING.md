# Como publicar uma nova versão

A versão exibida aos usuários e o link de download são decididos pela **API** (`ai_gauge_api`).
O GitHub Release serve apenas como arquivo dos pacotes.

1. **Versão no código** (mesmo número em todos): `core/updater.js` (`CURRENT_VERSION`), `core/telemetry.js`,
   `macos/build.sh` (Info.plist) e o `MyAppVersion` padrão em `windows/installer/AIGauge.iss`.
2. **Commit e tag:** `git tag v1.2.0 && git push origin main --tags`.
3. **CI (`Release Build`):** gera `AI-Gauge-Setup.exe`, ZIP do Windows, macOS, Linux e `SHA256SUMS.txt`
   e cria um Release em **rascunho (draft)**. Para testar sem tag: Actions → Release Build → Run workflow.
4. **Teste** o `AI-Gauge-Setup.exe` numa máquina Windows limpa.
5. **Publique o rascunho** no GitHub (só então `releases/latest` passa a apontar para ele).
6. **Atualize a API** (`TelemetryController.php`: `$latestVer` e, se mudar, `download_url`) e faça o deploy
   seguindo o fluxo da VPS (GitHub antes da VPS). Só depois disso os apps passam a avisar a atualização.
