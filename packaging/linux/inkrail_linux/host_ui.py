"""GTK3/WebKitGTK 4.1 writer window for the Linux Inkrail host.

Thread safety
-------------
``evaluate_js``, ``show_error``, ``focus_editor``, ``finish_close``,
``failed_close``, ``confirm_discard``, ``set_pdf_export_active``, ``schedule``,
``cancel_schedule``, ``run_dialog`` and ``print_pdf`` may be called from any
thread: they marshal all GTK work to the main loop with ``GLib.idle_add``.
``run_dialog`` blocks only the calling (RPC) thread while a modal dialog is
open; ``print_pdf`` with a callback is fully asynchronous.  The ``callback``
given to ``print_pdf`` and the ``close_request`` callback both run on the GTK
main thread.  Construction, signal handlers and native dialogs themselves
must stay on the main thread.
"""

from __future__ import annotations

import os
import sys
import threading
import traceback
import uuid
from typing import Callable, Optional
from urllib.parse import urlsplit

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gtk, WebKit2, GLib, Gio  # noqa: E402

CLOSE_WATCHDOG_MS = 12000
_ALLOWED_PATHS = frozenset(("/", "/index.html"))


def print_settings_for(width_pt: float, height_pt: float, output: str):
    """Build the zero-margin, file-backed print settings used for letters."""
    settings = Gtk.PrintSettings.new()
    settings.set_printer("Print to File")
    settings.set(Gtk.PRINT_SETTINGS_OUTPUT_URI, GLib.filename_to_uri(output, None))
    settings.set(Gtk.PRINT_SETTINGS_OUTPUT_FILE_FORMAT, "pdf")
    settings.set_paper_width(width_pt, Gtk.Unit.POINTS)
    settings.set_paper_height(height_pt, Gtk.Unit.POINTS)
    settings.set_orientation(Gtk.PageOrientation.PORTRAIT)
    page_setup = Gtk.PageSetup.new()
    page_setup.set_paper_size(Gtk.PaperSize.new_custom(
        "inkrail", "Inkrail sheet", width_pt, height_pt, Gtk.Unit.POINTS))
    page_setup.set_orientation(Gtk.PageOrientation.PORTRAIT)
    for setter in ("set_top_margin", "set_bottom_margin", "set_left_margin", "set_right_margin"):
        getattr(page_setup, setter)(0.0, Gtk.Unit.POINTS)
    return settings, page_setup


def print_webview_to_pdf(view, path, width_px, height_px, callback=None) -> bool:
    """Print a WebView into ``path`` using WebKitGTK's file backend.

    The print job is asynchronous. ``callback(success)`` is invoked on the GTK
    main thread, matching ``WebKit2.PrintOperation``'s ``finished``/``failed``
    signals. Returns ``False`` if WebKit printing could not be started.
    """
    width_pt = width_px * 72.0 / 96.0
    height_pt = height_px * 72.0 / 96.0
    directory = os.path.dirname(os.path.abspath(path)) or "."
    temporary = os.path.join(directory, ".inkrail-export-" + uuid.uuid4().hex + ".pdf")
    done = False
    view.get_settings().set_print_backgrounds(True)
    settings, page_setup = print_settings_for(width_pt, height_pt, temporary)

    def complete(success: bool, error: Optional[BaseException] = None) -> None:
        nonlocal done
        if done:
            return
        done = True
        if success:
            try:
                if not os.path.isfile(temporary) or os.path.getsize(temporary) == 0:
                    raise OSError("WebKit did not produce a PDF file.")
                os.replace(temporary, path)
            except OSError as failure:
                success, error = False, failure
        if not success:
            print(f"Inkrail PDF export failed: {error}", file=sys.stderr)
        try:
            os.unlink(temporary)
        except OSError:
            pass
        if callback is not None:
            callback(bool(success))

    try:
        operation = WebKit2.PrintOperation.new(view)
        operation.set_print_settings(settings)
        operation.set_page_setup(page_setup)
        timeout_id = GLib.timeout_add(
            60000, lambda: (complete(False, TimeoutError("Printing timed out.")), False)[1])
        real_complete = complete

        def complete(success, error=None):  # noqa: F811 - cancels the guard timer
            if timeout_id:
                GLib.source_remove(timeout_id)
            return real_complete(success, error)

        # These signals exist at runtime even though this typelib omits them.
        operation.connect("failed", lambda _op, error: complete(False, error))
        operation.connect("finished", lambda _op: complete(True))
        operation.print_()
        return True
    except Exception as error:
        print(f"Inkrail WebKit printing unavailable ({error}); using GTK fallback.",
              file=sys.stderr)
        return False


class InkrailWindow(Gtk.Window):
    """A locked-down WebKit window hosting the local Inkrail desk."""

    def __init__(
        self,
        title: str,
        url: str,
        close_request: Callable[[], None],
    ) -> None:
        super().__init__(title=title)
        if not callable(close_request):
            raise TypeError("close_request must be callable")
        self._close_request = close_request
        self._origin = self._desk_origin(url)
        self._close_pending = False
        self._can_close = False
        self._watchdog_id = 0
        self._pdf_export_active = False
        self._close_after_pdf = False
        self._discard_dialog_open = False
        self._menu_actions: list[Gio.SimpleAction] = []
        self._pdf_snapshot = None
        self._main_thread = threading.current_thread()

        self.set_default_size(1080, 760)
        self.set_size_request(640, 480)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect("delete-event", self._on_delete_event)

        settings = WebKit2.Settings.new()
        settings.set_enable_javascript(True)
        settings.set_enable_developer_extras(False)
        settings.set_javascript_can_open_windows_automatically(False)
        settings.set_print_backgrounds(True)
        # APIs removed in newer WebKitGTK are simply skipped where absent.
        for setter_name in ("set_enable_java", "set_enable_plugins"):
            setter = getattr(settings, setter_name, None)
            if setter is not None:
                setter(False)
        for setter_name in (
            "set_password_autosave_enabled",
            "set_autofill_enabled",
            "set_enable_password_autosave",
            "set_enable_autofill",
        ):
            setter = getattr(settings, setter_name, None)
            if setter is not None:
                setter(False)

        self.view = WebKit2.WebView.new_with_settings(settings)
        self.add(self.view)
        self.view.show()

        manager = self.view.get_website_data_manager()
        if manager is not None and hasattr(manager, "set_persistent_credential_storage_enabled"):
            manager.set_persistent_credential_storage_enabled(False)

        context = self.view.get_context()
        if context is not None:
            try:
                context.connect("download-started", self._on_download_started)
            except Exception:
                pass  # Signal is absent on some WebKitGTK builds.

        self.view.connect("decide-policy", self._on_decide_policy)
        self.view.connect("context-menu", self._on_context_menu)
        self.view.connect("permission-request", self._on_permission_request)
        self.view.load_uri(url)

    # ------------------------------------------------------------------
    # Origin / policy
    # ------------------------------------------------------------------
    @staticmethod
    def _desk_origin(url: str) -> tuple[str, str, int]:
        parts = urlsplit(url)
        if parts.scheme != "http" or not parts.hostname:
            raise ValueError("Inkrail can only load its local HTTP desk.")
        if parts.hostname.lower() != "127.0.0.1" or parts.username or parts.password:
            raise ValueError("The writing desk must be served from 127.0.0.1.")
        if parts.path not in _ALLOWED_PATHS or parts.query:
            raise ValueError("The writing desk must be served from /index.html.")
        try:
            return parts.scheme, parts.hostname.lower(), parts.port or 80
        except ValueError as error:
            raise ValueError("Invalid local port for the writing desk.") from error

    def _is_allowed_uri(self, uri: str) -> bool:
        try:
            parts = urlsplit(uri)
            port = parts.port or 80
        except (TypeError, ValueError):
            return False
        return (
            parts.scheme == self._origin[0]
            and (parts.hostname or "").lower() == self._origin[1]
            and port == self._origin[2]
            and not parts.username
            and not parts.password
            and parts.path in _ALLOWED_PATHS
            and not parts.query
        )

    def _on_decide_policy(self, view, decision, decision_type) -> bool:
        if decision_type == WebKit2.PolicyDecisionType.NEW_WINDOW_ACTION:
            decision.ignore()
            return True
        if decision_type == WebKit2.PolicyDecisionType.NAVIGATION_ACTION:
            request = getattr(decision, "get_request", lambda: None)()
            uri = request.get_uri() if request is not None else ""
            if self._is_allowed_uri(uri):
                decision.use()
            else:
                decision.ignore()
            return True
        # Response policies cover subresources; downloads are cancelled below.
        return False

    @staticmethod
    def _on_download_started(context, download) -> None:
        download.cancel()

    @staticmethod
    def _on_permission_request(view, request) -> bool:
        request.deny()
        return True

    def _on_context_menu(self, view, menu, event) -> bool:
        """Keep only the native editing commands, including clipboard actions."""
        try:
            menu.remove_all()

            def add_command(name: str, label: str, command: str) -> None:
                action = Gio.SimpleAction.new(name, None)
                action.connect(
                    "activate",
                    lambda _action, _parameter, command=command: view.execute_editing_command(
                        command
                    ),
                )
                self._menu_actions.append(action)
                menu.append(
                    WebKit2.ContextMenuItem.new_from_gaction(action, label, None)
                )

            add_command("inkrail-undo", "Undo", "Undo")
            add_command("inkrail-redo", "Redo", "Redo")
            for action_name in (
                "CUT",
                "COPY",
                "PASTE",
                "PASTE_AS_PLAIN_TEXT",
                "SELECT_ALL",
                "DELETE",
            ):
                action = getattr(WebKit2.ContextMenuAction, action_name, None)
                if action is None:
                    continue
                menu.append(WebKit2.ContextMenuItem.new_from_stock_action(action))
        except Exception:
            traceback.print_exc()
        # Returning False asks WebKit to show the menu we just built.
        return False

    # ------------------------------------------------------------------
    # Close handshake (mirrors WriterWindow.cs)
    # ------------------------------------------------------------------
    def _on_delete_event(self, _widget, _event) -> bool:
        if self._can_close:
            return False
        if self._close_pending:
            return True
        if self._pdf_export_active:
            # Preparing/printing the PDF precedes the close-time save.
            self._close_after_pdf = True
            return True
        self._close_pending = True
        self.view.set_sensitive(False)
        # The RPC host owns the save-confirmation watchdog; it calls
        # confirm_discard() if the desk does not report a completed save.
        try:
            self._close_request()
        except Exception:
            traceback.print_exc()
            self.failed_close()
        return True

    def _on_close_timeout(self) -> bool:
        self._watchdog_id = 0
        self.failed_close()
        return False

    def _clear_watchdog(self) -> None:
        if self._watchdog_id:
            GLib.source_remove(self._watchdog_id)
            self._watchdog_id = 0

    def finish_close(self) -> bool:
        """Confirm a saved close. Safe from any thread."""
        GLib.idle_add(self._finish_close_now)
        return True

    def _finish_close_now(self) -> bool:
        self._clear_watchdog()
        self._close_pending = False
        self._can_close = True
        self._pdf_export_active = False
        self._close_after_pdf = False
        self.view.set_sensitive(True)
        self.destroy()
        application = Gtk.Application.get_default()
        if application is not None:
            application.quit()
        Gtk.main_quit()
        return False

    def failed_close(self) -> bool:
        """Ask whether to discard unsaved writing. Safe from any thread."""
        GLib.idle_add(self._failed_close_now)
        return True

    def _failed_close_now(self) -> bool:
        if self._can_close or not self._close_pending or self._discard_dialog_open:
            return False
        self._discard_dialog_open = True
        self._clear_watchdog()
        self._close_pending = False
        self.view.set_sensitive(True)
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.NONE,
            text="Inkrail could not confirm that your writing was saved.",
        )
        dialog.format_secondary_text("Close anyway and lose any unsaved changes?")
        dialog.add_button("Keep writing", Gtk.ResponseType.CANCEL)
        danger = dialog.add_button("Close anyway", Gtk.ResponseType.YES)
        dialog.set_default_response(Gtk.ResponseType.YES)
        danger.get_style_context().add_class("destructive-action")
        try:
            response = dialog.run()
        finally:
            dialog.destroy()
            self._discard_dialog_open = False
        if response == Gtk.ResponseType.YES:
            self._finish_close_now()
        else:
            self.focus_editor()
        return False

    def confirm_discard(self) -> bool:
        """Alias used by RPC hosts that own the close watchdog themselves."""
        return self.failed_close()

    def run_dialog(self, func: Callable[[], object]) -> object:
        """Run a modal dialog callable on the GTK main thread and return its result.

        Safe from any thread.  The calling RPC thread waits while the dialog
        is open, mirroring the Windows host's modal message loop.
        """
        if threading.current_thread() is self._main_thread:
            return func()
        done = threading.Event()
        box: dict = {}

        def invoke() -> bool:
            try:
                box["value"] = func()
            except BaseException as error:  # re-raised on the calling thread
                box["error"] = error
            finally:
                done.set()
            return False

        GLib.idle_add(invoke)
        done.wait()
        if "error" in box:
            raise box["error"]
        return box.get("value")

    def schedule(self, milliseconds: int, callback: Callable[[], object]) -> int:
        """Run ``callback`` once after ``milliseconds``. Safe from any thread."""

        def fire() -> bool:
            try:
                callback()
            except Exception:
                traceback.print_exc()
            return False

        return GLib.timeout_add(max(0, int(milliseconds)), fire)

    def cancel_schedule(self, handle: int) -> None:
        """Cancel a handle returned by :meth:`schedule`. Safe from any thread."""
        if handle:
            GLib.source_remove(handle)

    def set_pdf_export_active(self, active: bool) -> bool:
        """Defer close requests while a PDF export is in progress.

        Clearing the flag resumes a close that was requested in the meantime,
        so the normal save-before-close handshake runs afterwards. Safe from
        any thread.
        """
        GLib.idle_add(self._set_pdf_export_active_now, bool(active))
        return True

    def _set_pdf_export_active_now(self, active: bool) -> bool:
        self._pdf_export_active = active
        if not active and self._close_after_pdf and not self._close_pending:
            self._close_after_pdf = False
            self._on_delete_event(self, None)
        return False

    # ------------------------------------------------------------------
    # Small helpers used by the RPC host
    # ------------------------------------------------------------------
    def evaluate_js(self, script: str) -> bool:
        """Queue ``script`` for the page on the GTK main loop. Safe anywhere."""
        GLib.idle_add(self._evaluate_js_now, str(script))
        return True

    def _evaluate_js_now(self, script: str) -> bool:
        try:
            if hasattr(self.view, "evaluate_javascript"):
                self.view.evaluate_javascript(script, -1, None)
            else:  # WebKitGTK < 2.40 compatibility.
                self.view.run_javascript(script, None, None)
        except Exception:
            traceback.print_exc()
        return False

    def show_error(self, message: str) -> bool:
        """Show a modal error dialog. Safe from any thread."""
        GLib.idle_add(self._show_error_now, str(message))
        return True

    def _show_error_now(self, message: str) -> bool:
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text=message,
        )
        try:
            dialog.run()
        finally:
            dialog.destroy()
        return False

    def focus_editor(self) -> bool:
        """Return keyboard focus to the editor. Safe from any thread."""
        GLib.idle_add(self._focus_editor_now)
        return True

    def _focus_editor_now(self) -> bool:
        if not self._can_close:
            self.view.grab_focus()
        return False

    # ------------------------------------------------------------------
    # PDF printing
    # ------------------------------------------------------------------
    def print_pdf(
        self,
        path: str,
        width_px: float,
        height_px: float,
        callback: Optional[Callable[[bool], None]] = None,
    ) -> bool:
        """Print the current page to ``path`` at an exact, margin-free size.

        ``width_px``/``height_px`` are CSS pixels (96 px per inch).  With a
        ``callback`` the call is fully asynchronous and the callback runs once
        on the GTK main thread.  Without one, a call from an RPC thread waits
        for completion (up to 60 s) and returns the success bool; a call from
        the GTK main thread schedules the work and returns ``True``.  Printing
        never opens a dialog or blocks the main loop waiting for user input.
        """
        target = os.fspath(path)
        width = float(width_px)
        height = float(height_px)
        if callback is None and threading.current_thread() is not self._main_thread:
            done = threading.Event()
            result: dict = {}

            def finish(success: bool) -> None:
                result["value"] = bool(success)
                done.set()

            GLib.idle_add(self._print_pdf_now, target, width, height, finish)
            if not done.wait(timeout=60):
                return False
            return bool(result.get("value", False))
        GLib.idle_add(self._print_pdf_now, target, width, height, callback)
        return True

    @staticmethod
    def _pdf_callback(callback: Optional[Callable[[bool], None]], success: bool) -> bool:
        if callback is not None:
            try:
                callback(bool(success))
            except Exception:
                traceback.print_exc()
        return False

    def _print_pdf_now(
        self,
        path: str,
        width_px: float,
        height_px: float,
        callback: Optional[Callable[[bool], None]],
    ) -> bool:
        def finished(success: bool) -> None:
            GLib.idle_add(self._pdf_callback, callback, success)

        if print_webview_to_pdf(self.view, path, width_px, height_px, finished):
            return False

        width_pt = width_px * 72.0 / 96.0
        height_pt = height_px * 72.0 / 96.0
        directory = os.path.dirname(os.path.abspath(path)) or "."
        temporary = os.path.join(directory, ".inkrail-export-" + uuid.uuid4().hex + ".pdf")
        settings, page_setup = print_settings_for(width_pt, height_pt, temporary)

        def complete(success: bool, error: Optional[BaseException] = None) -> None:
            if success:
                try:
                    if not os.path.isfile(temporary) or os.path.getsize(temporary) == 0:
                        raise OSError("GTK did not produce a PDF file.")
                    os.replace(temporary, path)
                except OSError as failure:
                    success, error = False, failure
            if not success:
                print(f"Inkrail PDF export failed: {error}", file=sys.stderr)
            try:
                os.unlink(temporary)
            except OSError:
                pass
            finished(success)

        self._gtk_pdf_fallback(settings, page_setup, width_pt, height_pt, complete)
        return False

    def _gtk_pdf_fallback(
        self,
        settings: Gtk.PrintSettings,
        page_setup: Gtk.PageSetup,
        width_pt: float,
        height_pt: float,
        complete: Callable[[bool, Optional[BaseException]], None],
    ) -> None:
        """Last-resort PDF backend; draws a full-document WebKit snapshot."""
        operation = Gtk.PrintOperation.new()
        operation.set_print_settings(settings)
        operation.set_default_page_setup(page_setup)
        operation.set_unit(Gtk.Unit.POINTS)
        operation.set_allow_async(True)
        operation.set_show_progress(False)
        operation.set_job_name("Inkrail letter")

        def draw_page(_operation, context, page_number) -> None:
            surface = self._pdf_snapshot
            if surface is None:
                return
            cr = context.get_cairo_context()
            scale = context.get_width() / max(float(surface.get_width()), 1.0)
            offset = page_number * (context.get_height() / scale)
            cr.save()
            cr.scale(scale, scale)
            cr.translate(0.0, -offset)
            cr.set_source_surface(surface, 0.0, 0.0)
            cr.paint()
            cr.restore()

        operation.connect("draw-page", draw_page)
        operation.connect(
            "done",
            lambda _op, result: complete(
                result == Gtk.PrintOperationResult.APPLY,
                None if result == Gtk.PrintOperationResult.APPLY else RuntimeError(
                    "The PDF printer did not complete."
                ),
            ),
        )

        def snapshot_ready(_view, result) -> None:
            try:
                self._pdf_snapshot = self.view.get_snapshot_finish(result)
            except Exception as error:
                complete(False, error)
                return
            try:
                operation.run(Gtk.PrintOperationAction.PRINT, self)
            except Exception as error:
                complete(False, error)

        try:
            self.view.get_snapshot(
                WebKit2.SnapshotRegion.FULL_DOCUMENT,
                WebKit2.SnapshotOptions(0),
                None,
                snapshot_ready,
            )
        except Exception as error:
            complete(False, error)
