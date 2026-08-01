# Trackit

A local-first Flutter spending tracker for IDR cash and digital balances.

## Build without Android Studio

The repository is built in GitHub Actions. Run the **Android APK** workflow from the Actions tab, then download the `trackit-debug-apk` artifact. The hosted runner cannot reach an emulator on your computer: `127.0.0.1:5555` is local to the machine running the installer.

The app starts with manual balances and captures only explicitly allowlisted payment notification packages. Android notification access is broad, so Trackit explains the access before opening Settings, processes supported formats locally, stores normalized candidates only, and requires review before importing uncertain spending. Replace the placeholder package IDs in `TrackitNotificationListener.kt` before device testing.

Gmail integration is intentionally deferred from the MVP because it requires a separate OAuth/API and privacy review.

## Local artifact installer

Requirements: Python 3.10+, `adb` on PATH, and an emulator/device listening at `127.0.0.1:5555`.

Create a fine-grained GitHub token with repository Actions read access, then run:

```text
set GITHUB_TOKEN=github_pat_...
python scripts/install_apk.py --repo 0xfrq/trackit --ref main
```

PowerShell:

```powershell
$env:GITHUB_TOKEN = 'github_pat_...'
python scripts/install_apk.py --repo 0xfrq/trackit --ref main
```

The token is read from `GITHUB_TOKEN` (or a hidden prompt), never printed or passed to `adb`. Test the local script without network access:

```text
python scripts/install_apk.py --self-test
```

The installer polls a successful workflow, downloads exactly one unexpired `trackit-debug-apk` artifact, checks its SHA-256, safely extracts the APK, connects to the explicit ADB serial, and installs with `adb install -r`.
