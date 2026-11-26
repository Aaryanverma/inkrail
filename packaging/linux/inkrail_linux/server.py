"""Loopback-only HTTP server for the web desk and its native RPC bridge.

``bridge.js`` uses this origin for automated smoke tests on Windows.  Linux uses
the same path: the editor loads from 127.0.0.1, sends requests to
``POST /_test/rpc`` and receives ``{id, value, error}`` replies.  Nothing is
listening on a network interface, and every request must carry the token that
was generated for this process.
"""

from __future__ import annotations

import hmac
import json
import mimetypes
import re
import secrets
import subprocess
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

from . import dialogs
from .library import Library

MAX_BODY = 16 * 1024 * 1024
DESK_PATH = "/index.html"

MIME = {
    ".css": "text/css; charset=utf-8",
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".ttf": "font/ttf",
    ".txt": "text/plain; charset=utf-8",
    ".wav": "audio/wav",
}


def new_token() -> str:
    return secrets.token_hex(32)


class DeskRPC:
    """Native services exposed to the desk.

    Window methods must be called on the GTK main thread; host_ui provides
    thread-safe helpers for dialogs and JavaScript scheduling.  This class
    itself runs on the HTTP server threads.
    """

    def __init__(self, library: Library, window, ui_root: Path):
        self.library = library
        self.window = window
        self.ui_root = ui_root.resolve()
        self.token = new_token()
        self.ready = False
        self.can_close = False
        self.close_pending = False
        self.pdf_export_active = False
        self.close_after_pdf_export = False
        self.exit_code = 0
        self.watchdog = None
        self.lock = threading.RLock()

    @property
    def library_path(self) -> str:
        # The port mirrors the C# property name; older helpers used snake_case.
        return getattr(self.library, "location", None) or self.library.Location

    def process(self, payload) -> dict:
        request_id = payload.get("id") if isinstance(payload, dict) else None
        try:
            if not isinstance(payload, dict):
                raise ValueError("Malformed RPC request.")
            if not hmac.compare_digest(str(payload.get("token", "")), self.token):
                raise PermissionError("This desk belongs to another Inkrail window.")
            op = payload.get("op")
            # bridge.js calls some operations with a bare boolean (for example
            # windowDirty(true) and endPdfExport(true)), not an argument object.
            args = payload.get("args", {})
            if not isinstance(op, str):
                raise ValueError("Malformed RPC request.")
            value = self.dispatch(op, args)
            return {"id": request_id, "value": value}
        except Exception as error:  # the desk shows the message to the writer
            return {"id": request_id, "error": str(error) or type(error).__name__}

    def dispatch(self, op: str, args: dict):
        with self.lock:
            if op == "boot":
                return self.library.boot()
            if op == "windowReady":
                self.ready = True
                self.window.focus_editor()
                return None
            if op == "windowDirty":
                # Always flush on close, even if only preferences have changed.
                return None
            if op == "windowClosed":
                if self.close_pending:
                    self._stop_watchdog()
                    self.can_close = True
                    self.window.finish_close()
                return None
            if op == "windowCloseFailed":
                if self.close_pending:
                    self.close_failed()
                return None
            if op == "import":
                return self.window.run_dialog(lambda: dialogs.import_letter(self.window))
            if op == "export":
                return self.window.run_dialog(
                    lambda: dialogs.export_text(
                        self.window,
                        args.get("text", ""),
                        args.get("body", ""),
                        bool(args.get("markdown", False)),
                    )
                )
            if op == "beginPdfExport":
                granted = not self.close_pending and not self.can_close and not self.pdf_export_active
                if granted:
                    self.pdf_export_active = True
                return granted
            if op == "exportPDF":
                if not self.pdf_export_active:
                    raise RuntimeError("PDF export has not started.")
                return self._export_pdf(args)
            if op == "endPdfExport":
                # app.js passes the finished flag itself, not {finished: ...}.
                finished = args.get("finished", False) if isinstance(args, dict) else bool(args)
                self.pdf_export_active = False
                resume_close = self.close_after_pdf_export and finished
                self.close_after_pdf_export = False
                if resume_close:
                    self.request_close(resume=True)
                return None
            if op == "changeStorage":
                destination = self.window.run_dialog(lambda: dialogs.choose_library_folder(self.window))
                if not destination:
                    return None
                self.library.relocate(destination)
                return self.library_path
            if op == "revealStorage":
                path = self.library_path
                if not Path(path).is_dir():
                    raise FileNotFoundError(path)
                subprocess.Popen(["xdg-open", path], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return None
            return self.library.dispatch(op, args)

    def _export_pdf(self, args: dict) -> bool:
        path = self.window.run_dialog(lambda: dialogs.choose_pdf_path(self.window, args.get("body", "")))
        if not path:
            return False
        width = float(args["width"])
        height = float(args["height"])
        result = self.window.print_pdf(path, width, height)
        if not result:
            raise OSError("The letter could not be exported as a PDF.")
        return True

    # -- close protocol -------------------------------------------------
    def request_close(self, resume: bool = False) -> None:
        """Called by the window when the writer tries to close it."""
        with self.lock:
            if self.can_close:
                return
            if not resume and not self.ready:
                self.can_close = True
                self.window.finish_close()
                return
            if self.pdf_export_active:
                self.close_after_pdf_export = True
                return
            if self.close_pending:
                return
            self.close_pending = True
            self.window.evaluate_js("window.dispatchEvent(new Event('inkrail-close-request'))")
            self._start_watchdog()

    def close_failed(self) -> None:
        with self.lock:
            self._stop_watchdog()
            if not self.close_pending or self.can_close:
                return
            self.close_pending = False
            self.window.confirm_discard()

    def _start_watchdog(self) -> None:
        self._stop_watchdog()
        self.watchdog = self.window.schedule(12000, self.close_failed)

    def _stop_watchdog(self) -> None:
        if self.watchdog is not None:
            self.window.cancel_schedule(self.watchdog)
            self.watchdog = None

    def abandon_pdf(self) -> None:
        """Used if the renderer disappears before it can end a print job."""
        with self.lock:
            self.pdf_export_active = False
            self.close_after_pdf_export = False


class DeskHandler(BaseHTTPRequestHandler):
    server_version = "Inkrail/1.0"
    protocol_version = "HTTP/1.1"

    @property
    def desk(self) -> "DeskServer":
        return self.server  # type: ignore[return-value]

    def do_GET(self) -> None:
        url = urlsplit(self.path)
        if url.path == "/_test/rpc":
            self._send(HTTPStatus.METHOD_NOT_ALLOWED, b"", "text/plain")
            return
        relative = unquote(url.path).lstrip("/")
        if not relative:
            relative = "index.html"
        root = self.desk.ui_root.resolve()
        target = (root / relative).resolve()
        if not target.is_relative_to(root) or not target.is_file():
            self._send(HTTPStatus.NOT_FOUND, b"Not found", "text/plain")
            return
        content = target.read_bytes()
        mime = MIME.get(target.suffix.lower()) or mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        self._send(HTTPStatus.OK, content, mime, extra={"Cache-Control": "no-store"})

    def do_POST(self) -> None:
        if urlsplit(self.path).path != "/_test/rpc":
            self._send(HTTPStatus.NOT_FOUND, b"Not found", "text/plain")
            return
        length = self.headers.get("Content-Length")
        try:
            size = int(length or "0")
        except ValueError:
            size = -1
        if size < 0 or size > MAX_BODY:
            self._send(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, b"Request too large", "text/plain")
            return
        try:
            payload = json.loads(self.rfile.read(size) or b"null")
        except (ValueError, UnicodeDecodeError):
            self._send(HTTPStatus.BAD_REQUEST, b"Malformed request", "text/plain")
            return
        reply = self.desk.rpc.process(payload)
        body = json.dumps(reply, ensure_ascii=True).encode("ascii")
        self._send(HTTPStatus.OK, body, "application/json; charset=utf-8",
                   extra={"Cache-Control": "no-store"})

    def _send(self, status: HTTPStatus, body: bytes, content_type: str, extra=None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD" and body:
            self.wfile.write(body)

    def log_message(self, fmt: str, *args) -> None:
        # Desk traffic is local and includes a per-process token in requests.
        return


class DeskServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, rpc: DeskRPC, ui_root: Path):
        self.rpc = rpc
        self.ui_root = ui_root.resolve()
        super().__init__(address, DeskHandler)

    @property
    def desk_url(self) -> str:
        host, port = self.server_address[:2]
        return f"http://{host}:{port}{DESK_PATH}#{self.rpc.token}"


def desk_token_from_url(url: str) -> str:
    """Small helper used by the smoke test."""
    return re.sub(r"^.*#", "", url)
