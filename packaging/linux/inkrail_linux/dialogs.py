"""Native GTK file dialogs for the Linux Inkrail host.

The public functions mirror ``packaging/windows/host/FileDialogs.cs``.  They
open modal dialogs, so they must be called on the GTK main thread.  I/O and
decoding errors are raised as ``OSError`` with a message suitable for showing
to the writer; a cancelled dialog returns ``None``/``False``.
"""

from __future__ import annotations

import os
import re
import unicodedata
import uuid
from typing import Optional

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

UTF8_BOM = b"\xef\xbb\xbf"
UTF16_LE_BOM = b"\xff\xfe"
UTF16_BE_BOM = b"\xfe\xff"
DECODE_ERROR = "Save a copy in UTF-8 or in UTF-16 with a byte order mark and try again."

MARKDOWN_EXTENSIONS = frozenset((".md", ".markdown", ".mdown", ".mkd"))
_INVALID_CHARS = frozenset('/\\%:*?"<>|')
_RESERVED_NAME = re.compile(
    r"^(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)",
    re.IGNORECASE,
)
_LINE_BREAKS = re.compile(r"\r\n|[\r\n\v\f\u0085\u2028\u2029]")
_MAX_NAME_ELEMENTS = 64


def _is_mark(ch: str) -> bool:
    """Combining marks and variation selectors belong to the preceding glyph."""
    code = ord(ch)
    return (
        unicodedata.category(ch) in ("Mn", "Me")
        or unicodedata.combining(ch) != 0
        or 0xFE00 <= code <= 0xFE0F
        or 0xE0100 <= code <= 0xE01EF
    )


def _graphemes(text: str) -> list[str]:
    """A small, dependency-free approximation of Intl.Segmenter(grapheme)."""
    result: list[str] = []
    index = 0
    length = len(text)
    while index < length:
        start = index
        char = text[index]
        index += 1
        # Regional indicator pairs (flags) form one cluster.
        if (
            0x1F1E6 <= ord(char) <= 0x1F1FF
            and index < length
            and 0x1F1E6 <= ord(text[index]) <= 0x1F1FF
        ):
            index += 1
        while index < length:
            if _is_mark(text[index]):
                index += 1
            elif text[index] == "\u200d" and index + 1 < length:
                # Emoji/person ZWJ sequences: join the ZWJ and its next glyph.
                index += 2
                while index < length and _is_mark(text[index]):
                    index += 1
            else:
                break
        result.append(text[start:index])
    return result


def export_name(body: str) -> str:
    """Derive a safe file name from the first non-empty line of ``body``."""
    first = next(
        (line.strip() for line in _LINE_BREAKS.split(body or "") if line.strip()),
        "Untitled letter",
    )
    title = "".join(_graphemes(first)[:_MAX_NAME_ELEMENTS])
    safe = "".join(
        "-"
        if char in _INVALID_CHARS or ord(char) < 32 or ord(char) == 127
        else char
        for char in title
    ).strip().strip(".").strip()
    if not safe:
        return "Untitled letter"
    if _RESERVED_NAME.match(safe):
        safe = "_" + safe
    return safe


def _pattern_filter(name: str, pattern: str) -> Gtk.FileFilter:
    file_filter = Gtk.FileFilter()
    file_filter.set_name(name)
    file_filter.add_pattern(pattern)
    return file_filter


def _save_path(
    parent: Optional[Gtk.Window],
    body: str,
    extension: str,
    filter_name: str,
) -> Optional[str]:
    title = "Keep a copy of your letter"
    dialog = Gtk.FileChooserDialog(
        title=title,
        parent=parent,
        action=Gtk.FileChooserAction.SAVE,
        buttons=("Cancel", Gtk.ResponseType.CANCEL, "Save", Gtk.ResponseType.OK),
    )
    dialog.set_default_response(Gtk.ResponseType.OK)
    dialog.set_do_overwrite_confirmation(True)
    dialog.set_select_multiple(False)
    dialog.set_current_name(f"{export_name(body)}.{extension}")
    dialog.add_filter(_pattern_filter(filter_name, f"*.{extension}"))
    dialog.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
    try:
        response = dialog.run()
        filename = dialog.get_filename()
        if filename is None:
            filename = os.path.join(
                dialog.get_current_folder() or os.getcwd(), dialog.get_current_name()
            )
    finally:
        dialog.destroy()
    if response != Gtk.ResponseType.OK or not filename:
        return None
    filename = os.path.abspath(filename)
    if not os.path.splitext(filename)[1]:
        filename += "." + extension
        if os.path.exists(filename) and not _confirm_overwrite(parent, os.path.basename(filename)):
            return None
    return filename


def _confirm_overwrite(parent: Optional[Gtk.Window], filename: str) -> bool:
    dialog = Gtk.MessageDialog(
        transient_for=parent,
        modal=True,
        message_type=Gtk.MessageType.QUESTION,
        buttons=Gtk.ButtonsType.NONE,
        text=f"A file named “{filename}” already exists. Do you want to replace it?",
    )
    dialog.format_secondary_text("Replacing it will overwrite its contents.")
    dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
    replace = dialog.add_button("Replace", Gtk.ResponseType.OK)
    dialog.set_default_response(Gtk.ResponseType.CANCEL)
    replace.get_style_context().add_class("destructive-action")
    try:
        return dialog.run() == Gtk.ResponseType.OK
    finally:
        dialog.destroy()


def _write_atomically(path: str, content: bytes) -> None:
    """Write ``content`` as UTF-8 via a temp file beside ``path``, then replace."""
    directory = os.path.dirname(os.path.abspath(path)) or "."
    temporary = os.path.join(directory, ".inkrail-export-" + uuid.uuid4().hex + ".tmp")
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except OSError as error:
        raise OSError(f"Could not write '{path}': {error.strerror or error}") from error
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        except OSError:
            pass


def import_letter(parent: Optional[Gtk.Window]) -> Optional[dict]:
    """Open a letter and return ``{'text': ..., 'markdown': bool}`` or ``None``."""
    dialog = Gtk.FileChooserDialog(
        title="Import a letter",
        parent=parent,
        action=Gtk.FileChooserAction.OPEN,
        buttons=("Cancel", Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.OK),
    )
    dialog.set_default_response(Gtk.ResponseType.OK)
    dialog.set_select_multiple(False)
    dialog.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
    text_files = Gtk.FileFilter()
    text_files.set_name("Text and Markdown files")
    for pattern in ("*.txt", "*.md", "*.markdown", "*.mdown", "*.mkd"):
        text_files.add_pattern(pattern)
    dialog.add_filter(text_files)
    all_files = Gtk.FileFilter()
    all_files.set_name("All files")
    all_files.add_pattern("*")
    dialog.add_filter(all_files)
    try:
        response = dialog.run()
        filename = dialog.get_filename()
    finally:
        dialog.destroy()
    if response != Gtk.ResponseType.OK or not filename:
        return None
    filename = os.path.abspath(filename)
    if not os.path.isfile(filename):
        raise OSError(f"Cannot open '{filename}': not a file.")
    try:
        with open(filename, "rb") as stream:
            data = stream.read()
    except OSError as error:
        raise OSError(f"Could not read '{filename}': {error.strerror or error}") from error
    try:
        if data.startswith(UTF16_LE_BOM):
            text = data[2:].decode("utf-16-le", errors="strict")
        elif data.startswith(UTF16_BE_BOM):
            text = data[2:].decode("utf-16-be", errors="strict")
        else:
            if data.startswith(UTF8_BOM):
                data = data[3:]
            text = data.decode("utf-8", errors="strict")
    except UnicodeError as error:
        raise OSError(DECODE_ERROR) from error
    extension = os.path.splitext(filename)[1].lower()
    return {"text": text, "markdown": extension in MARKDOWN_EXTENSIONS}


def export_text(
    parent: Optional[Gtk.Window], text: str, body: str, markdown: bool
) -> bool:
    """Ask for a destination and save ``text``; return ``False`` if cancelled."""
    extension = "md" if markdown else "txt"
    path = _save_path(
        parent,
        body,
        extension,
        "Markdown file" if markdown else "Text file",
    )
    if path is None:
        return False
    _write_atomically(path, (text or "").encode("utf-8"))
    return True


def choose_pdf_path(parent: Optional[Gtk.Window], body: str) -> Optional[str]:
    """Ask for a PDF destination and return its absolute path, or ``None``."""
    return _save_path(parent, body, "pdf", "PDF document")


def choose_library_folder(parent: Optional[Gtk.Window]) -> Optional[str]:
    """Choose a folder for the library, allowing new folders to be created."""
    dialog = Gtk.FileChooserDialog(
        title="Choose an empty folder for your Inkrail library",
        parent=parent,
        action=Gtk.FileChooserAction.SELECT_FOLDER,
        buttons=("Cancel", Gtk.ResponseType.CANCEL, "Select", Gtk.ResponseType.OK),
    )
    dialog.set_default_response(Gtk.ResponseType.OK)
    dialog.set_select_multiple(False)
    dialog.set_create_folders(True)
    dialog.set_show_hidden(False)
    dialog.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
    try:
        response = dialog.run()
        filename = dialog.get_filename()
    finally:
        dialog.destroy()
    if response != Gtk.ResponseType.OK or not filename:
        return None
    folder = os.path.abspath(filename)
    if not os.path.isdir(folder):
        raise OSError(f"Not a folder: '{folder}'.")
    return folder
