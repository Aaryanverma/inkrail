# Inkrail for Linux

Paper, ink, and a little room to write.

Run `./inkrail` from this folder, or install it with
`bash install.sh --bundle <this-folder>` (add `--install-deps` to install
missing system packages with sudo). The app launcher entry is installed for
the current user only.

## Requirements

- Linux with GTK 3, WebKitGTK 4.1 and their GObject introspection bindings
  (`python-gobject`).
- GStreamer base/good plugins for the typewriter sounds.
- `xdg-open` for **Show local files**.

Arch: `sudo pacman -S gtk3 webkit2gtk-4.1 python-gobject gstreamer gst-plugins-base gst-plugins-good xdg-utils`

Debian/Ubuntu: `sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1 gstreamer1.0-plugins-base gstreamer1.0-plugins-good xdg-utils`

Fedora: `sudo dnf install gtk3 webkit2gtk4.1 python3-gobject gstreamer1.0-plugins-base gstreamer1.0-plugins-good xdg-utils`

## Your writing

Letters are stored as JSON in `$XDG_DATA_HOME/inkrail/Library/Letters`
(usually `~/.local/share/inkrail/Library/Letters`), with recently deleted
letters in `Recently Deleted` for 30 days. **Make it yours → Storage** shows
the folder and can move the library to an empty folder you choose. The format
is identical to the Mac and Windows builds, so you can copy a library between
them.

Open **Make it yours** with `Ctrl+,`. `Alt+F` opens the file and writing menu.

## Verifying the bundle

`python3 build-linux.py --check --bundle <this-folder>` verifies every file
against `files.sha256`.

Inkrail is MIT licensed; see `LICENSE.txt` and `Sound-Credits.txt`.
