#!/usr/bin/env python3
"""Smoke-test the Linux host's loopback desk and cross-platform library format."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packaging/linux"))

TOKEN = "linux-smoke-test-token"
PROCESS = None


def rpc(url: str, op: str, args=None, token=TOKEN):
    payload = json.dumps({"id": 1, "token": token, "op": op, "args": args or {}}).encode()
    request = urllib.request.Request(
        urllib.parse.urljoin(url, "/_test/rpc"), data=payload,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=10) as response:
        result = json.load(response)
    if result.get("error"):
        raise AssertionError(f"{op} failed: {result['error']}")
    return result.get("value")


def start(profile: Path) -> str:
    command = [sys.executable, str(ROOT / "packaging/linux/inkrail"), "--headless",
               "--profile", str(profile), "--token", TOKEN]
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    deadline = time.time() + 15
    while time.time() < deadline:
        line = process.stdout.readline().strip()
        if line.startswith("http://127.0.0.1:"):
            return line, process
        if process.poll() is not None:
            raise AssertionError(f"Host exited: {process.stderr.read()}")
    process.kill()
    raise AssertionError("Host did not report its URL")


def stop(process) -> None:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()


def main() -> int:
    global PROCESS
    with tempfile.TemporaryDirectory(prefix="inkrail-linux-") as folder:
        profile = Path(folder) / "profile"
        url, PROCESS = start(profile)
        try:
            boot = rpc(url, "boot")
            assert boot["available"] is True, boot
            assert boot["pages"] == [], boot
            assert (profile / "Library/Letters").is_dir()
            assert (profile / "Library/Recently Deleted").is_dir()

            with urllib.request.urlopen(url.split("#")[0], timeout=5) as response:
                assert b"<title>Inkrail</title>" in response.read()
            with urllib.request.urlopen(urllib.parse.urljoin(url, "bridge.js"), timeout=5) as response:
                assert b"export function call" in response.read()

            payload = json.dumps({"id": 2, "token": "wrong-token", "op": "boot", "args": {}}).encode()
            request = urllib.request.Request(urllib.parse.urljoin(url, "/_test/rpc"), data=payload,
                                             headers={"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(request, timeout=5) as response:
                assert "another Inkrail window" in json.load(response)["error"]

            preferences = {"nightMode": True, "fontSize": 24, "writingFont": "courier"}
            assert rpc(url, "settings", {"preferences": preferences, "selectedID": None}) is None
            saved = json.loads((profile / "preferences.json").read_text())
            assert saved["preferences"]["fontSize"] == 24, saved

            page_id = str(uuid.uuid4()).upper()
            now = "2026-01-02T03:04:05.000Z"
            page = {"id": page_id, "createdAt": now, "modifiedAt": now,
                    "text": "Dear Linux,\n\nIt writes here too.\n",
                    "formatting": [], "privateTitle": "A first letter"}
            assert rpc(url, "save", page) is None
            listed = rpc(url, "list", {"trash": False})["pages"]
            assert [p["id"] for p in listed] == [page_id]
            assert listed[0]["text"] == page["text"]

            page["text"] += "One more line.\n"
            page["modifiedAt"] = "2026-01-02T03:05:05.000Z"
            assert rpc(url, "save", page) is None
            assert rpc(url, "list", {"trash": False})["pages"][0]["text"] == page["text"]
            assert (profile / "Library/Letters" / f"{page_id}.json.bak").is_file()

            assert rpc(url, "trash", {"id": page_id}) is None
            assert rpc(url, "list", {"trash": False})["pages"] == []
            assert [p["id"] for p in rpc(url, "list", {"trash": True})["pages"]] == [page_id]
            assert (profile / "Library/Recently Deleted" / f"{page_id}.trashinfo").is_file()

            assert rpc(url, "restore", {"id": page_id}) is None
            assert [p["id"] for p in rpc(url, "list", {"trash": False})["pages"]] == [page_id]
            cleanup = rpc(url, "cleanup")
            assert "removedIDs" in cleanup and "warnings" in cleanup, cleanup

            # Older Mac letters used seconds since 2001-01-01 rather than ISO dates.
            from inkrail_linux.library import Library
            legacy_id = str(uuid.uuid4()).upper()
            legacy = {"id": legacy_id, "createdAt": 789000000, "modifiedAt": 789000000,
                      "text": "From the Mac archive"}
            (profile / "Library/Letters" / f"{legacy_id}.json").write_text(
                json.dumps(legacy), encoding="utf-8")
            converted = rpc(url, "list", {"trash": False})["pages"]
            legacy_page = next(p for p in converted if p["id"] == legacy_id)
            assert legacy_page["createdAt"].startswith("2026-"), legacy_page

            stop(PROCESS)
            PROCESS = None
            destination = Path(folder) / "moved-library"
            destination.mkdir()
            Library(profile).relocate(destination)
            assert (destination / "Letters" / f"{page_id}.json").is_file()

            url, PROCESS = start(profile)
            boot = rpc(url, "boot")
            assert boot["path"] == str(destination), boot
            assert {p["id"] for p in boot["pages"]} == {page_id, legacy_id}
            print("Linux host smoke test passed: boot, RPC, static desk, save, backup, "
                  "trash, restore, cleanup, legacy dates, relocation and reopen.")
            return 0
        finally:
            if PROCESS is not None:
                stop(PROCESS)


if __name__ == "__main__":
    sys.exit(main())
