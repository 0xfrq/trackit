#!/usr/bin/env python3
"""Download a successful Trackit GitHub Actions APK and install it locally."""
from __future__ import annotations

import argparse
import getpass
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ARTIFACT = "trackit-debug-apk"
SERIAL = "127.0.0.1:5555"
TERMINAL = {"completed", "failure", "cancelled", "skipped", "timed_out"}

class InstallerError(RuntimeError):
    pass


def api_request(url: str, token: str) -> bytes:
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "trackit-apk-installer",
    })
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            raise InstallerError("GitHub rejected the PAT; check Actions read access.") from error
        raise InstallerError(f"GitHub API request failed with HTTP {error.code}.") from error
    except urllib.error.URLError as error:
        raise InstallerError(f"Could not reach GitHub: {error.reason}") from error


def json_request(url: str, token: str) -> dict:
    return json.loads(api_request(url, token))


def find_run(repo: str, workflow: str, ref: str, token: str, run_id: str | None, poll_seconds: int, timeout: int) -> dict:
    if run_id:
        url = f"https://api.github.com/repos/{repo}/actions/runs/{urllib.parse.quote(run_id)}"
    else:
        query = urllib.parse.urlencode({"branch": ref, "event": "push", "per_page": 20})
        url = f"https://api.github.com/repos/{repo}/actions/workflows/{urllib.parse.quote(workflow)}/runs?{query}"
    deadline = time.monotonic() + timeout
    while True:
        data = json_request(url, token)
        run = data if run_id else next((item for item in data.get("workflow_runs", []) if item.get("head_branch") == ref), None)
        if run and run.get("status") in TERMINAL:
            if run.get("conclusion") != "success":
                raise InstallerError(f"Workflow ended as {run.get('conclusion') or run.get('status')}.")
            return run
        if time.monotonic() >= deadline:
            raise InstallerError("Timed out waiting for a completed workflow run.")
        time.sleep(poll_seconds)


def download_artifact(repo: str, run: dict, token: str) -> bytes:
    data = json_request(f"https://api.github.com/repos/{repo}/actions/runs/{run['id']}/artifacts?per_page=100", token)
    matches = [item for item in data.get("artifacts", []) if item.get("name") == ARTIFACT and not item.get("expired")]
    if len(matches) != 1:
        raise InstallerError(f"Expected one unexpired {ARTIFACT} artifact, found {len(matches)}.")
    return api_request(matches[0]["archive_download_url"], token)


def extract_apk(archive: bytes, directory: Path) -> Path:
    with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
        files = [item for item in bundle.infolist() if not item.is_dir()]
        apks = [item for item in files if Path(item.filename).suffix.lower() == ".apk"]
        if len(apks) != 1:
            raise InstallerError(f"Expected exactly one APK in artifact, found {len(apks)}.")
        item = apks[0]
        destination = (directory / Path(item.filename).name).resolve()
        if destination.parent != directory.resolve():
            raise InstallerError("Artifact contains an unsafe APK path.")
        with bundle.open(item) as source, destination.open("wb") as output:
            output.write(source.read())
        return destination


def install(apk: Path, dry_run: bool) -> None:
    if dry_run:
        print(f"dry-run: would install {apk} on {SERIAL}")
        return
    try:
        subprocess.run(["adb", "connect", SERIAL], check=True, capture_output=True, text=True)
        devices = subprocess.run(["adb", "devices"], check=True, capture_output=True, text=True).stdout
        if f"{SERIAL}\tdevice" not in devices:
            raise InstallerError(f"ADB device {SERIAL} is not connected.")
        subprocess.run(["adb", "-s", SERIAL, "install", "-r", str(apk)], check=True)
    except FileNotFoundError as error:
        raise InstallerError("adb was not found on PATH.") from error
    except subprocess.CalledProcessError as error:
        raise InstallerError(f"ADB installation failed with exit code {error.returncode}.") from error


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp)
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as bundle:
            bundle.writestr("app-debug.apk", b"apk")
        apk = extract_apk(buffer.getvalue(), path)
        assert apk.read_bytes() == b"apk"
        unsafe = io.BytesIO()
        with zipfile.ZipFile(unsafe, "w") as bundle:
            bundle.writestr("nested/app.apk", b"apk")
        assert extract_apk(unsafe.getvalue(), path).name == "app.apk"
    print("self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="0xfrq/trackit")
    parser.add_argument("--workflow", default="android.yml")
    parser.add_argument("--ref", default="main")
    parser.add_argument("--run-id")
    parser.add_argument("--poll-seconds", type=int, default=10)
    parser.add_argument("--timeout-seconds", type=int, default=900)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    token = os.environ.get("GITHUB_TOKEN") or getpass.getpass("GitHub PAT (hidden): ")
    if not token:
        raise InstallerError("A GitHub PAT is required.")
    run = find_run(args.repo, args.workflow, args.ref, token, args.run_id, max(1, args.poll_seconds), args.timeout_seconds)
    archive = download_artifact(args.repo, run, token)
    with tempfile.TemporaryDirectory(prefix="trackit-") as temp:
        apk = extract_apk(archive, Path(temp))
        print(f"Downloaded APK sha256={hashlib.sha256(apk.read_bytes()).hexdigest()}")
        install(apk, args.dry_run)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except InstallerError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
