"""Entry point for the Linux Inkrail desk."""

from __future__ import annotations

import argparse
import fcntl
import os
import sys
import threading
from pathlib import Path

from .assets import prepare_ui
from .library import Library
from .server import DeskRPC, DeskServer

DEFAULT_UI = Path(".build/linux-ui")


class HeadlessWindow:
    """Dialog-free stand-in used by the automated RPC smoke test."""

    def __init__(self):
        self.scripts = []

    def run_dialog(self, func):
        return None

    def print_pdf(self, path, width, height):
        return False

    def focus_editor(self):
        return None

    def evaluate_js(self, script):
        self.scripts.append(script)

    def schedule(self, milliseconds, callback):
        return None

    def cancel_schedule(self, handle):
        return None

    def finish_close(self):
        return None

    def confirm_discard(self):
        return None

    def show_error(self, message):
        print("Inkrail:", message, file=sys.stderr)


def default_profile() -> Path:
    root = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    return Path(root) / "inkrail"


def acquire_instance_lock(profile: Path):
    """Keep one desk per library, as the Windows host does with a mutex."""
    profile.mkdir(parents=True, exist_ok=True)
    handle = (profile / ".inkrail.lock").open("a+")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        return None
    return handle


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Inkrail — a quiet place to write")
    parser.add_argument("-data", "--profile", type=Path, default=None,
                        help="library profile folder (default: $XDG_DATA_HOME/inkrail)")
    parser.add_argument("--ui", type=Path, default=None,
                        help="folder holding the shared web desk")
    parser.add_argument("--port", type=int, default=0,
                        help="loopback port (0 chooses a free port)")
    parser.add_argument("--token", default=None,
                        help=argparse.SUPPRESS)  # deterministic automated tests only
    parser.add_argument("--headless", action="store_true",
                        help=argparse.SUPPRESS)  # RPC smoke test without a display
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    profile = (args.profile or default_profile()).expanduser().resolve()
    ui = (args.ui or DEFAULT_UI).expanduser()
    lock = acquire_instance_lock(profile)
    if lock is None:
        print("Inkrail is already open for this library. Switch to its existing window.",
              file=sys.stderr)
        return 1

    try:
        root = Path(__file__).resolve().parents[3]
        if args.ui is not None:
            candidate = ui.expanduser().resolve()
            ui_root = candidate if (candidate / "index.html").is_file() else prepare_ui(candidate)
        else:
            # A source checkout can always rebuild the desk from the shared UI.
            candidate = (root / DEFAULT_UI).resolve() if (root / "packaging/windows/ui/index.html").is_file() \
                else (Path.cwd() / DEFAULT_UI).resolve()
            # Always refresh: prepare_ui copies only files whose mtime changed,
            # so an edited desk is never hidden by an older cached copy.
            ui_root = prepare_ui(candidate)
        library = Library(profile)
        rpc = DeskRPC(library, HeadlessWindow(), ui_root)
        if args.token:
            rpc.token = args.token
        server = DeskServer(("127.0.0.1", args.port), rpc, ui_root)

        if args.headless:
            print(server.desk_url, flush=True)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                threading.Event().wait()
            except KeyboardInterrupt:
                pass
            finally:
                server.shutdown()
            return rpc.exit_code

        try:
            import gi
            gi.require_version("Gtk", "3.0")
            gi.require_version("WebKit2", "4.1")
            from gi.repository import Gtk
            from .host_ui import InkrailWindow
        except Exception as error:
            print("Inkrail needs GTK 3 and WebKitGTK 4.1 with their GObject "
                  f"introspection bindings.\n  {error}\n"
                  "Arch: sudo pacman -S gtk3 webkit2gtk-4.1 python-gobject\n"
                  "Debian/Ubuntu: sudo apt install python3-gi gir1.2-gtk-3.0 "
                  "gir1.2-webkit2-4.1", file=sys.stderr)
            return 2

        window = InkrailWindow("Inkrail", server.desk_url, rpc.request_close)
        rpc.window = window
        thread = threading.Thread(target=server.serve_forever, name="inkrail-rpc", daemon=True)
        thread.start()
        try:
            window.show_all()
            Gtk.main()
        except KeyboardInterrupt:
            rpc.exit_code = 1
        finally:
            server.shutdown()
            server.server_close()
        return rpc.exit_code
    except Exception as error:
        print(f"Inkrail could not start: {error}", file=sys.stderr)
        return 1
    finally:
        if lock is not None:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            lock.close()


if __name__ == "__main__":
    sys.exit(main())
