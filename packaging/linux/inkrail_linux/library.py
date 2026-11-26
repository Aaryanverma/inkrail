"""Storage backend for Inkrail's v0.1.1 profile on Linux.

This module is a port of ``packaging/windows/host/Library.cs``.  The profile
layout, file names, JSON payloads and recovery journal are intentionally the
same as in the Windows and macOS builds so that a library can be moved between
them without conversion.

Differences from the C# implementation are only the platform primitives:

* named mutexes become ``fcntl.flock`` locks on files in the profile and in the
  library folder;
* ``File.Replace`` becomes a same-directory staging file plus renames (a
  readable ``.bak`` covers the short interval between the two renames);
* ``DateTimeOffset`` values are represented by timezone-aware ``datetime``
  objects and emitted in the same ISO-8601 form used by System.Text.Json.

No third-party packages are used.
"""

from __future__ import annotations

import contextlib
import copy
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import tempfile
import time
import uuid
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Iterator

__all__ = ["Library", "LibraryError", "InvalidData"]


class LibraryError(Exception):
    """A storage error whose message is suitable for display in the UI."""


class InvalidData(LibraryError):
    """Equivalent of C#'s ``InvalidDataException`` for stored JSON."""


_UUID_TEXT = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\Z"
)
_FOUNDATION_EPOCH = 978307200  # 2001-01-01T00:00:00Z in Unix seconds.
_FOUNDATION_MIN = -63113904000
_FOUNDATION_MAX = 252423993600
_UNIX_MIN = -62135596800
_UNIX_MAX = 253402300800
_UNIX_EPOCH = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
_RETENTION = dt.timedelta(days=30)
_LOCK_TIMEOUT = 3.0

# System.Text.Json's default encoder escapes these HTML-sensitive ASCII
# characters even though JSON does not require it.  Matching the escape style
# keeps files written by this port byte-identical to files written on Windows.
_ESCAPED_ASCII = {"<": "003C", ">": "003E", "&": "0026", "'": "0027", "+": "002B"}
_SHORT_ESCAPES = {
    "\b": "\\b",
    "\f": "\\f",
    "\n": "\\n",
    "\r": "\\r",
    "\t": "\\t",
}


def _name(identifier: uuid.UUID) -> str:
    """The uppercase, hyphenated file-name form of a letter ID (Guid 'D')."""
    return str(identifier).upper()


def _hash(data: bytes | None) -> str | None:
    """Uppercase SHA-256 hex, like ``Convert.ToHexString`` in C#."""
    return None if data is None else hashlib.sha256(data).hexdigest().upper()


def _is_file(path: str) -> bool:
    """Return True for a regular file; reject directories and symlinks."""
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return False
    if not stat.S_ISREG(info.st_mode):
        raise LibraryError(f"Expected a regular file at {path}.")
    return True


def _require_directory(path: str) -> None:
    try:
        info = os.lstat(path)
    except OSError as error:
        raise LibraryError(f"Expected a library folder at {path}.") from error
    if not stat.S_ISDIR(info.st_mode):  # lstat also rejects symlinked folders.
        raise LibraryError(f"Expected a library folder at {path}.")


def _is_directory(path: str) -> bool:
    try:
        return stat.S_ISDIR(os.lstat(path).st_mode)
    except OSError:
        return False


def _create_folder(path: str) -> None:
    os.makedirs(path, exist_ok=True)
    _require_directory(path)


def _read_optional(path: str) -> bytes | None:
    return _read_all(path) if _is_file(path) else None


def _read_all(path: str) -> bytes:
    with open(path, "rb") as source:
        return source.read()


def _delete_if_exists(path: str) -> None:
    """``File.Delete`` semantics: deleting a missing file is not an error."""
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def _move_file(source: str, destination: str) -> None:
    """``File.Move`` semantics: never overwrite an existing destination."""
    if os.path.lexists(destination):
        raise LibraryError(f"Cannot move {source} to an existing file at {destination}.")
    os.replace(source, destination)


def _fsync_directory(path: str) -> None:
    """Durably commit a rename; ignore volumes that do not support this."""
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


def _write_file(path: str, data: bytes, replace: bool, backup: str | None = None) -> None:
    """Stage bytes on the same volume, then install them atomically.

    The C# original uses ``File.Replace``, which installs the new bytes and
    moves the displaced bytes to ``backup`` in one operation.  POSIX has no
    portable atomic exchange, so the displaced file is renamed first and the
    staged file second.  A reader that stops between the two renames sees a
    missing primary and recovers it from ``.bak`` exactly as on Windows.
    """
    folder = os.path.dirname(path) or "."
    fd, temporary = tempfile.mkstemp(prefix=".inkrail-", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        if replace:
            if backup is not None:
                if not os.path.lexists(path):
                    raise LibraryError(f"Cannot replace a file that does not exist: {path}.")
                os.replace(path, backup)
            os.replace(temporary, path)
        else:
            if os.path.lexists(path):
                raise LibraryError(f"Cannot create a file when that file already exists: {path}.")
            os.replace(temporary, path)
        _fsync_directory(folder)
    finally:
        _delete_if_exists(temporary)


@contextlib.contextmanager
def _lock_directory(folder: str, filename: str) -> Iterator[None]:
    """Hold an exclusive, cross-process ``flock`` for up to three seconds.

    A lock file in the folder is the Linux equivalent of the C# named mutex:
    it also serializes separate ``Library`` objects in this process because
    each one opens its own file description.  A read-only volume falls back to
    locking the directory itself, which needs no write access.
    """
    target = os.path.join(folder, filename)
    flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(target, flags, 0o600)
    except OSError:
        try:
            fd = os.open(
                folder, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_CLOEXEC
            )
        except OSError as error:
            raise LibraryError(f"Could not lock {folder}: {error}") from error
    try:
        deadline = time.monotonic() + _LOCK_TIMEOUT
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except InterruptedError:
                continue
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise LibraryError("The library is busy.")
                time.sleep(0.02)
        yield
    finally:
        with contextlib.suppress(OSError):
            fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _quote_json(text: str) -> str:
    """Serialize a JSON string with System.Text.Json's default escaping."""
    pieces = ['"']
    for character in text:
        if character == '"':
            pieces.append('\\"')
        elif character == "\\":
            pieces.append("\\\\")
        elif character in _SHORT_ESCAPES:
            pieces.append(_SHORT_ESCAPES[character])
        elif character in _ESCAPED_ASCII:
            pieces.append("\\u" + _ESCAPED_ASCII[character])
        else:
            code = ord(character)
            if code < 0x20:
                pieces.append(f"\\u{code:04X}")
            elif code < 0x7F:
                pieces.append(character)
            elif code <= 0xFFFF:
                pieces.append(f"\\u{code:04X}")
            else:
                # UTF-16 surrogate pair, as emitted by the default encoder.
                code -= 0x10000
                pieces.append(f"\\u{0xD800 + (code >> 10):04X}")
                pieces.append(f"\\u{0xDC00 + (code & 0x3FF):04X}")
    pieces.append('"')
    return "".join(pieces)


def _dump_json(value: Any) -> str:
    """Compact, deterministic JSON with stable object key order."""
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return _quote_json(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return json.dumps(value, allow_nan=False)
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(_dump_json(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(
            _quote_json(str(key)) + ":" + _dump_json(item) for key, item in value.items()
        ) + "}"
    raise LibraryError(f"Cannot store a value of type {type(value).__name__} in JSON.")


def _json_bytes(value: Any) -> bytes:
    return _dump_json(value).encode("utf-8")


def _reject_constant(text: str) -> Any:
    raise InvalidData(f"Invalid JSON number: {text}")


def _parse_json(data: bytes) -> Any:
    try:
        return json.loads(data, parse_constant=_reject_constant)
    except (ValueError, UnicodeDecodeError) as error:
        raise InvalidData("Invalid JSON.") from error


def _read_object(data: bytes) -> dict[str, Any]:
    value = _parse_json(data)
    if not isinstance(value, dict):
        raise InvalidData("Expected a JSON object.")
    return value


def _parse_iso_date(value: str) -> dt.datetime:
    text = value.strip()
    if text.endswith(("Z", "z")):
        text = text[:-1] + "+00:00"
    try:
        moment = dt.datetime.fromisoformat(text)
    except ValueError as error:
        raise InvalidData("Invalid letter date.") from error
    if moment.tzinfo is None:
        # System.Text.Json treats an offset-less string as local time; Linux
        # hosts run in UTC, so UTC is the unambiguous equivalent here.
        moment = moment.replace(tzinfo=dt.timezone.utc)
    return moment


def _read_date(value: Any) -> dt.datetime:
    """Read a System.Text.Json date: ISO string or Foundation seconds number."""
    if isinstance(value, str):
        return _parse_iso_date(value)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        seconds = Decimal(str(value))
        if Decimal(_FOUNDATION_MIN) <= seconds < Decimal(_FOUNDATION_MAX):
            try:
                total = Decimal(_FOUNDATION_EPOCH) + seconds
                micros = int((total * 1_000_000).to_integral_value(rounding=ROUND_HALF_UP))
                return _UNIX_EPOCH + dt.timedelta(microseconds=micros)
            except (OverflowError, ValueError):
                pass
    raise InvalidData("Invalid letter date.")


def _format_date(moment: dt.datetime) -> str:
    """Format a date the way System.Text.Json formats a ``DateTimeOffset``."""
    offset = moment.utcoffset() or dt.timedelta(0)
    sign = "-" if offset < dt.timedelta(0) else "+"
    minutes = abs(int(offset.total_seconds())) // 60
    zone = f"{sign}{minutes // 60:02d}:{minutes % 60:02d}"
    result = moment.strftime("%Y-%m-%dT%H:%M:%S")
    if moment.microsecond:
        result += "." + f"{moment.microsecond:06d}".rstrip("0")
    return result + zone


def _page_date(page: dict[str, Any], field: str) -> dt.datetime:
    if field not in page:
        raise InvalidData("Invalid letter date.")
    return _read_date(page[field])


def _page_id(args: Any) -> uuid.UUID:
    if not isinstance(args, dict) or not isinstance(args.get("id"), str):
        raise InvalidData("A letter ID is required.")
    try:
        return uuid.UUID(args["id"])
    except ValueError as error:
        raise InvalidData(f"Invalid letter ID: {args['id']}.") from error


@dataclass(frozen=True)
class _Revision:
    """Hashes observed the last time a letter was listed or saved."""

    primary: str | None
    backup: str | None = None


def _page_ids(folder: str) -> list[uuid.UUID]:
    """Letter IDs inferred from ``*.json``, ``*.json.bak`` and ``*.transfer``."""
    ids: list[uuid.UUID] = []
    seen: set[uuid.UUID] = set()
    for name in os.listdir(folder):
        if len(name) <= 36 or not _UUID_TEXT.fullmatch(name[:36]):
            continue
        if name[36:] not in (".json", ".json.bak", ".transfer"):
            continue
        identifier = uuid.UUID(name[:36])
        if identifier not in seen:
            seen.add(identifier)
            ids.append(identifier)
    return ids


def _prefix(folder: str) -> str:
    return folder if folder.endswith(os.sep) else folder + os.sep


def _trim(folder: str) -> str:
    return folder.rstrip(os.sep) or os.sep


def _inventory(root: str) -> dict[str, str | None]:
    """Relative path -> SHA-256 hex for files, ``None`` for directories."""
    entries: dict[str, str | None] = {}

    def visit(folder: str) -> None:
        for name in sorted(os.listdir(folder)):
            path = os.path.join(folder, name)
            relative = os.path.relpath(path, root)
            info = os.lstat(path)
            if stat.S_ISLNK(info.st_mode):
                raise LibraryError(f"The library contains a link at {relative}.")
            if stat.S_ISDIR(info.st_mode):
                entries[relative] = None
                visit(path)
            elif stat.S_ISREG(info.st_mode):
                digest = hashlib.sha256()
                with open(path, "rb") as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        digest.update(chunk)
                entries[relative] = digest.hexdigest().upper()
            else:
                raise LibraryError(f"Expected a regular file at {path}.")

    visit(root)
    return entries


def _probe_writable(folder: str) -> None:
    """Confirm that a copied library can accept atomic saves on its new volume."""
    fd, path = tempfile.mkstemp(prefix=".inkrail-", suffix=".tmp", dir=folder)
    try:
        os.write(fd, b"\x01")
        os.fsync(fd)
    finally:
        os.close(fd)
        _delete_if_exists(path)


class Library:
    """The storage service shared by the native host and its UI bridge."""

    def __init__(self, profile_directory: str | os.PathLike[str]) -> None:
        self.profile = os.path.abspath(os.fspath(profile_directory))
        self.location = os.path.join(self.profile, "Library")
        self._settings: dict[str, Any] = {}
        self._settings_hash: str | None = None
        self._settings_ready = False
        self._available = False
        self._revisions: dict[uuid.UUID, _Revision] = {}

    @property
    def Location(self) -> str:
        """Compatibility with callers ported from the C# ``Location`` property."""
        return self.location

    @property
    def _settings_file(self) -> str:
        return os.path.join(self.profile, "preferences.json")

    @property
    def _letters(self) -> str:
        return os.path.join(self.location, "Letters")

    @property
    def _trash(self) -> str:
        return os.path.join(self.location, "Recently Deleted")

    @contextlib.contextmanager
    def _profile_lock(self) -> Iterator[None]:
        os.makedirs(self.profile, exist_ok=True)
        with _lock_directory(self.profile, ".inkrail-profile.lock"):
            yield

    @contextlib.contextmanager
    def _library_lock(self) -> Iterator[None]:
        # A disconnected or invalid library has nothing to lock; the checks
        # below it report the missing folder in the same words as the C# host.
        if _is_directory(self.location):
            with _lock_directory(self.location, ".inkrail-library.lock"):
                yield
        else:
            yield

    def _check_folders(self) -> None:
        _require_directory(self.location)
        _require_directory(self._letters)
        _require_directory(self._trash)

    @staticmethod
    def _changed() -> None:
        raise LibraryError("The saved copy changed. Export your edits and reopen Inkrail.")

    def _page_path(self, identifier: uuid.UUID, trash: bool) -> str:
        folder = self._trash if trash else self._letters
        return os.path.join(folder, _name(identifier) + ".json")

    def _receipt(self, identifier: uuid.UUID) -> str:
        return os.path.join(self._trash, _name(identifier) + ".trashinfo")

    def _marker(self, identifier: uuid.UUID) -> str:
        return os.path.join(self._trash, _name(identifier) + ".transfer")

    def _decode(self, data: bytes, identifier: uuid.UUID) -> dict[str, Any]:
        """Validate a letter and normalize older Foundation numeric dates."""
        page = _parse_json(data)
        if not isinstance(page, dict):
            raise InvalidData(
                f"Unrecognized letter or mismatched ID for {_name(identifier)}."
            )
        stored_id = page.get("id")
        if not isinstance(stored_id, str):
            raise InvalidData(
                f"Unrecognized letter or mismatched ID for {_name(identifier)}."
            )
        try:
            actual = uuid.UUID(stored_id)
        except ValueError as error:
            raise InvalidData(
                f"Unrecognized letter or mismatched ID for {_name(identifier)}."
            ) from error
        if (
            actual != identifier
            or not isinstance(page.get("text"), str)
            or "createdAt" not in page
            or "modifiedAt" not in page
        ):
            raise InvalidData(
                f"Unrecognized letter or mismatched ID for {_name(identifier)}."
            )
        first = _read_date(page["createdAt"])
        last = _read_date(page["modifiedAt"])
        if isinstance(page["createdAt"], str) and isinstance(page["modifiedAt"], str):
            return page
        # Foundation's older JSON date representation counts seconds from
        # 1 January 2001.  Normalize both dates while keeping every unknown
        # field of the letter untouched.
        normalized = copy.deepcopy(page)
        normalized["createdAt"] = _format_date(first)
        normalized["modifiedAt"] = _format_date(last)
        return normalized

    def _try_decode(
        self, data: bytes | None, identifier: uuid.UUID
    ) -> tuple[bool, dict[str, Any] | None]:
        if data is None:
            return False, None
        try:
            return True, self._decode(data, identifier)
        except (InvalidData, ValueError, TypeError):
            return False, None

    def _verify_revision(
        self, identifier: uuid.UUID, path: str, primary: bytes | None
    ) -> None:
        known = self._revisions.get(identifier)
        if _hash(primary) != (known.primary if known else None):
            self._changed()
        if known is not None and known.backup is not None:
            if _hash(_read_optional(path + ".bak")) != known.backup:
                self._changed()

    def _recovery_path(self, identifier: uuid.UUID, extension: str) -> str:
        recovery = os.path.join(self.location, "Recovery")
        _create_folder(recovery)
        return os.path.join(
            recovery, f"{_name(identifier)}-{uuid.uuid4().hex}.{extension}"
        )

    def _save(self, page: dict[str, Any]) -> None:
        if not isinstance(page, dict):
            raise InvalidData("Expected a JSON object.")
        identifier = _page_id(page)
        data = _json_bytes(page)
        self._decode(data, identifier)  # Reject unreadable letters before writing.
        self._reconcile(identifier)
        path = self._page_path(identifier, False)
        previous = _read_optional(path)
        self._verify_revision(identifier, path, previous)
        has_backup = _is_file(path + ".bak")
        if identifier not in self._revisions and (
            has_backup
            or _is_file(self._page_path(identifier, True))
            or _is_file(self._page_path(identifier, True) + ".bak")
        ):
            raise LibraryError("A letter with this ID already exists.")
        # Keep the readable .bak when repairing a damaged primary; otherwise
        # ReplaceFile-style capture puts the displaced bytes in the backup.
        displaced = None
        if previous is not None:
            readable, _ = self._try_decode(previous, identifier)
            displaced = path + ".bak" if readable else self._recovery_path(identifier, "damaged")
        _write_file(path, data, previous is not None, displaced)
        self._revisions[identifier] = _Revision(_hash(data))
        if displaced is not None and _hash(_read_optional(displaced)) != _hash(previous):
            conflict = self._recovery_path(identifier, "conflict")
            shutil.copyfile(displaced, conflict)
            raise LibraryError(
                "Your edits were saved. Another version changed during the save "
                f"and was preserved at {conflict}."
            )

    def _commit_settings(self, next_settings: dict[str, Any]) -> None:
        if not self._settings_ready:
            raise LibraryError("The original preferences could not be read.")
        previous = _read_optional(self._settings_file)
        if _hash(previous) != self._settings_hash:
            raise LibraryError("Preferences changed on disk. Reopen Inkrail before saving.")
        data = _json_bytes(next_settings)
        displaced = (
            None
            if previous is None
            else self._settings_file + "." + uuid.uuid4().hex + ".previous"
        )
        _write_file(self._settings_file, data, previous is not None, displaced)
        self._settings_hash = _hash(data)
        self._settings = next_settings
        if displaced is not None and _hash(_read_optional(displaced)) == _hash(previous):
            _delete_if_exists(displaced)

    def _list_pages(self, trash: bool, warnings: list[str]) -> list[dict[str, Any]]:
        pages: list[dict[str, Any]] = []
        for identifier in sorted(_page_ids(self._trash if trash else self._letters)):
            try:
                self._reconcile(identifier)
                path = self._page_path(identifier, trash)
                primary = _read_optional(path)
                backup_hash: str | None = None
                readable, page = self._try_decode(primary, identifier)
                if not readable:
                    backup = _read_optional(path + ".bak")
                    if backup is None and primary is None:
                        continue
                    readable, page = self._try_decode(backup, identifier)
                    if not readable or page is None:
                        raise InvalidData(
                            f"Could not read the letter {_name(identifier)} or its backup."
                        )
                    warnings.append(
                        f"Opened the previous saved copy of {_name(identifier)}."
                    )
                    backup_hash = _hash(backup)
                if not trash:
                    self._revisions[identifier] = _Revision(_hash(primary), backup_hash)
                pages.append(page)
            except Exception as error:
                warnings.append(str(error))
        pages.sort(key=lambda page: _page_date(page, "modifiedAt"), reverse=True)
        return pages

    def _write_receipt(self, identifier: uuid.UUID, moment: dt.datetime) -> None:
        path = self._receipt(identifier)
        data = _json_bytes(
            {
                "version": 1,
                "id": _name(identifier),
                "deletedAt": int(moment.timestamp()),
            }
        )
        _write_file(path, data, _is_file(path))

    def _move_letter(self, identifier: uuid.UUID, deleting: bool) -> None:
        self._reconcile(identifier)
        source = self._page_path(identifier, not deleting)
        destination = self._page_path(identifier, deleting)
        if _is_file(destination) or _is_file(destination + ".bak"):
            raise LibraryError("The destination already contains this letter.")
        primary = _read_optional(source)
        backup = _read_optional(source + ".bak")
        if deleting:
            self._verify_revision(identifier, source, primary)
        readable, _ = self._try_decode(primary, identifier)
        if not readable:
            backup_readable, _ = self._try_decode(backup, identifier)
            if not backup_readable or backup is None:
                raise InvalidData("Neither saved copy of this letter is readable.")
            _write_file(
                source,
                backup,
                primary is not None,
                self._recovery_path(identifier, "damaged") if primary is not None else None,
            )
            primary = backup
            if deleting:
                self._revisions[identifier] = _Revision(_hash(primary))
        if deleting:
            self._write_receipt(identifier, dt.datetime.now(dt.timezone.utc))
        _write_file(
            self._marker(identifier),
            b"trash-v1" if deleting else b"restore-v1",
            False,
        )
        try:
            if backup is not None:
                _move_file(source + ".bak", destination + ".bak")
            _move_file(source, destination)
        finally:
            # Also runs when either move fails: a half-finished transfer is
            # rolled back here or on the next launch.
            self._finish_transfer(identifier)
        if deleting:
            self._revisions.pop(identifier, None)
        else:
            self._revisions[identifier] = _Revision(_hash(primary))

    def _finish_transfer(self, identifier: uuid.UUID) -> None:
        """Resolve a journaled move using the primary rename as the commit point."""
        marker = self._marker(identifier)
        journal = _read_optional(marker)
        if journal is None:
            return
        try:
            text = journal.decode("utf-8")
        except UnicodeDecodeError as error:
            raise InvalidData(f"Unrecognized transfer at {marker}.") from error
        if text == "trash-v1":
            deleting = True
        elif text == "restore-v1":
            deleting = False
        else:
            raise InvalidData(f"Unrecognized transfer at {marker}.")
        source = self._page_path(identifier, not deleting)
        destination = self._page_path(identifier, deleting)
        pending = _is_file(source)
        if pending == _is_file(destination):
            raise LibraryError(f"The interrupted transfer needs attention at {marker}.")
        if pending and _is_file(destination + ".bak"):
            _move_file(destination + ".bak", source + ".bak")
        if pending == deleting and _is_file(self._receipt(identifier)):
            _delete_if_exists(self._receipt(identifier))
        _delete_if_exists(marker)

    def _read_deletion_date(self, identifier: uuid.UUID) -> dt.datetime | None:
        data = _read_optional(self._receipt(identifier))
        if data is None:
            return None
        try:
            receipt = _parse_json(data)
        except InvalidData:
            return None
        if not isinstance(receipt, dict):
            return None
        version = receipt.get("version")
        if not isinstance(version, int) or isinstance(version, bool) or not -2147483648 <= version <= 2147483647:
            return None
        if version != 1:
            raise InvalidData("Unrecognized deletion record version.")
        stored_id = receipt.get("id")
        if not isinstance(stored_id, str):
            return None
        try:
            actual = uuid.UUID(stored_id)
        except ValueError:
            return None
        if actual != identifier or "deletedAt" not in receipt:
            return None
        date = receipt["deletedAt"]
        if isinstance(date, str):
            try:
                return _parse_iso_date(date)
            except InvalidData:
                return None
        if isinstance(date, (int, float)) and not isinstance(date, bool):
            seconds = Decimal(str(date))
            if Decimal(_UNIX_MIN) <= seconds < Decimal(_UNIX_MAX):
                try:
                    return _UNIX_EPOCH + dt.timedelta(seconds=int(seconds))
                except (OverflowError, ValueError):
                    return None
        return None

    def _reconcile(self, identifier: uuid.UUID) -> None:
        """Reunite backups split by interrupted or pre-journal transfers."""
        self._finish_transfer(identifier)
        active = self._page_path(identifier, False)
        deleted = self._page_path(identifier, True)
        active_backup, trash_backup = active + ".bak", deleted + ".bak"
        if not _is_file(active) and _is_file(deleted) and _is_file(active_backup):
            current = self._decode(_read_all(deleted), identifier)
            previous = self._decode(_read_all(active_backup), identifier)
            prior_date = _page_date(previous, "modifiedAt")
            deletion_date = self._read_deletion_date(identifier)
            if (
                _is_file(trash_backup)
                or deletion_date is None
                or deletion_date < prior_date
                or _page_date(current, "createdAt") != _page_date(previous, "createdAt")
                or _page_date(current, "modifiedAt") < prior_date
            ):
                raise LibraryError(f"A split letter needs attention at {active_backup}.")
            _move_file(active_backup, trash_backup)
        elif _is_file(active) and not _is_file(deleted) and _is_file(trash_backup):
            candidate = _read_all(trash_backup)
            prior = self._decode(candidate, identifier)
            readable, current = self._try_decode(_read_all(active), identifier)
            if readable and current is not None and (
                _page_date(current, "createdAt") != _page_date(prior, "createdAt")
                or _page_date(current, "modifiedAt") < _page_date(prior, "modifiedAt")
            ):
                raise LibraryError(f"A split letter needs attention at {trash_backup}.")
            other = _read_optional(active_backup)
            if other is None:
                _move_file(trash_backup, active_backup)
            elif other == candidate:
                _delete_if_exists(trash_backup)
            elif not self._try_decode(other, identifier)[0]:
                _write_file(
                    active_backup,
                    candidate,
                    True,
                    self._recovery_path(identifier, "damaged"),
                )
                _delete_if_exists(trash_backup)
            else:
                raise LibraryError(
                    f"Two different backups were kept for {_name(identifier)}."
                )

    def _cleanup(self, removed: list[str], warnings: list[str]) -> None:
        """Apply the 30-day Recently Deleted retention rule, with receipts."""
        now = dt.datetime.now(dt.timezone.utc)
        for identifier in sorted(_page_ids(self._trash)):
            try:
                self._reconcile(identifier)
                path = self._page_path(identifier, True)
                main = _read_optional(path)
                backup = _read_optional(path + ".bak")
                if main is None and backup is None:
                    continue
                if _is_file(self._page_path(identifier, False)) or _is_file(
                    self._page_path(identifier, False) + ".bak"
                ):
                    raise LibraryError("Both Letters and Recently Deleted contain this ID.")
                if (main is not None and not self._try_decode(main, identifier)[0]) or (
                    backup is not None and not self._try_decode(backup, identifier)[0]
                ):
                    raise InvalidData("A saved copy could not be identified.")
                deleted = self._read_deletion_date(identifier)
                if deleted is None:
                    self._write_receipt(identifier, now)
                    continue
                if now - deleted < _RETENTION:
                    continue
                _delete_if_exists(path + ".bak")
                _delete_if_exists(path)
                _delete_if_exists(self._receipt(identifier))
                removed.append(_name(identifier))
            except Exception as error:
                warnings.append(
                    f"Recently Deleted kept {_name(identifier)}: {error}"
                )

    def _check_current_location(self) -> None:
        current = _read_optional(self._settings_file)
        if _hash(current) == self._settings_hash:
            return
        saved = None if current is None else _read_object(current).get("libraryLocation")
        root = (
            os.path.join(self.profile, "Library")
            if not isinstance(saved, str) or not saved
            else os.path.abspath(saved)
        )
        if _prefix(_trim(root)).lower() != _prefix(_trim(self.location)).lower():
            raise LibraryError(
                "Another copy of Inkrail changed the library folder. Export "
                "pending edits and reopen Inkrail."
            )

    def boot(self) -> dict[str, Any]:
        """Open the profile, run overdue trash cleanup and list active letters."""
        warnings: list[str] = []
        trash_warnings: list[str] = []
        try:
            with self._profile_lock():
                original = _read_optional(self._settings_file)
                self._settings = {} if original is None else _read_object(original)
                saved = self._settings.get("libraryLocation")
                if isinstance(saved, str) and saved:
                    if not os.path.isabs(saved):
                        raise InvalidData("The saved library path must be absolute.")
                    self.location = os.path.abspath(saved)
                else:
                    _create_folder(self.location)
                    _create_folder(self._letters)
                    _create_folder(self._trash)
                self._settings_hash = _hash(original)
                self._settings_ready = True
                self._check_folders()
                with self._library_lock():
                    removed: list[str] = []
                    self._cleanup(removed, trash_warnings)
                    pages = self._list_pages(False, warnings)
            self._available = True
            return {
                "settings": self._settings,
                "available": True,
                "path": self.location,
                "pages": pages,
                "warnings": warnings,
                "trashWarning": "\n".join(trash_warnings),
            }
        except Exception as error:
            self._available = False
            return {
                "settings": self._settings,
                "available": False,
                "path": self.location,
                "pages": [],
                "warnings": [],
                "trashWarning": "",
                "error": str(error),
            }

    def dispatch(self, operation: str, args: Any = None) -> Any:
        """Run one serialized storage operation and return its JSON result."""
        with self._profile_lock():
            with self._library_lock():
                if operation == "settings":
                    if not isinstance(args, dict):
                        raise InvalidData("Expected a JSON object.")
                    next_settings = copy.deepcopy(self._settings)
                    preferences = next_settings.get("preferences")
                    if not isinstance(preferences, dict):
                        preferences = {}
                    incoming = args.get("preferences")
                    if incoming is not None:
                        if not isinstance(incoming, dict):
                            raise InvalidData("Expected a JSON object.")
                        preferences.update(copy.deepcopy(incoming))
                    next_settings["preferences"] = preferences
                    next_settings["selectedID"] = copy.deepcopy(args.get("selectedID"))
                    self._commit_settings(next_settings)
                    return None
                if not self._available:
                    raise LibraryError("The library is unavailable.")
                self._check_current_location()
                self._check_folders()
                warnings: list[str] = []
                if operation == "save":
                    self._save(args)
                    return None
                if operation == "list":
                    trash = bool(args.get("trash")) if isinstance(args, dict) else False
                    return {"pages": self._list_pages(trash, warnings), "warnings": warnings}
                if operation == "cleanup":
                    removed: list[str] = []
                    self._cleanup(removed, warnings)
                    return {"warnings": warnings, "removedIDs": removed}
                if operation in ("trash", "restore"):
                    self._move_letter(_page_id(args), operation == "trash")
                    return None
                raise LibraryError(f"Unknown library operation: {operation}")

    def relocate(self, destination: str | os.PathLike[str]) -> None:
        """Copy the whole library to an empty folder, then select that folder.

        The C# host always boots before offering relocation.  A freshly
        constructed Python object can also be asked directly, so load the
        profile first; an unusable profile still fails as it does in C#.
        """
        if not self._available and not self.boot()["available"]:
            raise LibraryError("The library is unavailable.")
        with self._profile_lock():
            with self._library_lock():
                if not self._available:
                    raise LibraryError("The library is unavailable.")
                self._check_current_location()
                self._check_folders()
                destination = _trim(os.path.abspath(os.fspath(destination)))
                source = _trim(os.path.realpath(self.location))
                target_root = _trim(os.path.realpath(destination))
                source_prefix, target_prefix = _prefix(source).lower(), _prefix(target_root).lower()
                if (
                    source_prefix.startswith(target_prefix)
                    or target_prefix.startswith(source_prefix)
                ):
                    raise LibraryError("Choose a folder outside the current library.")
                if not _is_directory(target_root) or os.listdir(target_root):
                    raise LibraryError("Choose an empty destination folder.")
                original = _inventory(source)
                for relative, digest in original.items():
                    source_item = os.path.join(source, relative)
                    target_item = os.path.join(target_root, relative)
                    if digest is None:
                        os.mkdir(target_item)
                    else:
                        with open(source_item, "rb") as source_file, open(
                            target_item, "xb"
                        ) as target_file:
                            shutil.copyfileobj(source_file, target_file)
                for root in (source, target_root):
                    snapshot = _inventory(root)
                    if len(snapshot) != len(original) or any(
                        key not in snapshot or snapshot[key] != digest
                        for key, digest in original.items()
                    ):
                        raise LibraryError(
                            "The library copy could not be verified. The original "
                            "folder remains selected."
                        )
                for folder in (
                    target_root,
                    os.path.join(target_root, "Letters"),
                    os.path.join(target_root, "Recently Deleted"),
                ):
                    _probe_writable(folder)
                next_settings = copy.deepcopy(self._settings)
                next_settings["libraryLocation"] = destination
                self._commit_settings(next_settings)
                self.location = destination
