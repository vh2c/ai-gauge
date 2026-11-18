# How to publish a new version

The version shown to users and the download link are decided by the **API** (`ai_gauge_api`).
The GitHub Release only serves as an archive of the packages.

1. **Version in the code** (same number everywhere): `core/updater.js` (`CURRENT_VERSION`), `core/telemetry.js`,
   `macos/build.sh` (Info.plist) and the default `MyAppVersion` in `windows/installer/AIGauge.iss`.
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
