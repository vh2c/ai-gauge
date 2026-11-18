# How to publish a new version

The version shown to users and the download link are decided by the **API** (`ai_gauge_api`).
The GitHub Release only serves as an archive of the packages.

1. **Version in the code** (same number everywhere): `core/updater.js` (`CURRENT_VERSION`), `core/telemetry.js`,
   `macos/build.sh` (Info.plist) and the default `MyAppVersion` in `windows/installer/AIGauge.iss`.
2. **Commit and tag:** `git tag v1.2.0 && git push origin main --tags`.
3. **CI (`Release Build`):** builds `AI-Gauge-Setup.exe`, the Windows, macOS and Linux ZIPs and `SHA256SUMS.txt`,
   and creates a **draft** Release. To test without a tag: Actions → Release Build → Run workflow.
4. **Test** `AI-Gauge-Setup.exe` on a clean Windows machine.
5. **Publish the draft** on GitHub (only then does `releases/latest` point to it).
6. **Update the API** (`TelemetryController.php`: `$latestVer` and, if it changes, `download_url`) and deploy
   following the VPS flow (GitHub before the VPS). Only after that do the apps start announcing the update.
