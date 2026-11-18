# How to publish a new version

The version shown to users and the download link are decided by the **API** (`ai_gauge_api`).
The GitHub Release only serves as an archive of the packages.

1. **Version in the code** (same number everywhere): `core/updater.js` (`CURRENT_VERSION`; the only version the app sends), the fallback in `.github/workflows/release.yml`,
   `macos/build.sh` (Info.plist, two fields) and the default `MyAppVersion` in `windows/installer/AIGauge.iss` (two places).
2. **Commit and tag:** `git tag -a v1.2.0 -m "AI Gauge v1.2.0" && git push origin main --tags`.
3. **CI (`Release Build`):** builds `AI-Gauge-Setup.exe`, the Windows, macOS and Linux ZIPs and `SHA256SUMS.txt`,
   and creates a **draft** Release. To test without a tag: Actions → Release Build → Run workflow
   (this builds the packages but does not create a release).
4. **Test** `AI-Gauge-Setup.exe` on a clean Windows machine, and the macOS ZIP on a Mac other than the build machine.
5. **Write the release notes** (English) on the draft, then **publish it** on GitHub:
   `gh release edit v1.2.0 --title "AI Gauge v1.2.0" --notes-file notes.md --draft=false --latest`
   (only then does `releases/latest` point to it).
6. **Update the API** (`TelemetryController.php`: `$latestVer` and, if it changes, `download_url`) and deploy
   following the VPS flow (GitHub before the VPS: commit, push, `git status` on the VPS, backup, `git pull origin main`).
   Only after that do the apps start announcing the update. Publish the GitHub release first, so the link never
   points to an older release.

## Notes

- **Tests:** run `node tests/updater.test.js`, `node tests/last_good.test.js` and `node tests/claude_file.test.js` before releasing. It checks, with a fake API and a throw-away HOME, that the app contacts
  the server only at startup (and once per 24h if left open), that PRO sends only `machine_id` + version, and that opt-out sends nothing.
- **API contact rules** live in `core/updater.js`; the apps just pass `--startup` to the engine on their first run. If you change what is
  sent, update the "Telemetry & Privacy" section of the README in the same commit.
- **Deploy order for telemetry changes:** deploy the API (`TelemetryController.php`) **before** releasing apps that send the minimal PRO payload,
  otherwise an older API would store `os = Unknown` for PRO devices.

- **Install docs:** `INSTALL.md` is the single install guide (security warnings, Node.js on macOS, checksums, troubleshooting,
  AI-assistant prompt). Keep it in sync with the installers; the README links to it. Download links use
  `releases/latest/download/<file>`, so they always match the published release and its `SHA256SUMS.txt`.

- **Packages in the repo:** `releases/v1.1/` holds the ZIPs linked from the README. Refresh them when the
  README links should follow a new version. macOS: `macos/build.sh`, then
  `ditto -c -k --keepParent --norsrc --noextattr "AI Gauge.app" AI-Gauge-macOS-vh2c.zip` (avoids `._*` files).
- **macOS binary:** universal (arm64 for macOS 11+, x86_64 for macOS 13+), ad-hoc signed, **not notarized**.
  First launch needs `xattr -cr "/Applications/AI Gauge.app"`.
- **Windows installer:** not code-signed, so SmartScreen may warn ("More info → Run anyway").
- **Re-running a tag:** if the CI fails after tagging and no release was published, fix the workflow, push, then
  delete and recreate the tag (`git push origin :refs/tags/v1.x.y`, `git tag -d v1.x.y`, tag again).

## Code signing (not set up yet)

- **macOS:** Apple Developer Program (about US$ 99/year), "Developer ID Application" certificate, then sign and
  notarize in CI (`codesign`, `notarytool`, `stapler`). This removes the `xattr` step.
- **Windows:** SignPath Foundation (free for open source), Azure Trusted Signing, or an OV/EV certificate.
- Certificates and passwords go in **GitHub Secrets**, never in the repository or in chat.
