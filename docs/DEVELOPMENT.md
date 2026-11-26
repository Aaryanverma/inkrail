# Inkrail v0.1.2 development notes

[Back to the user guide](../README.md)

These instructions use the v0.1.2 source tree. The Mac app uses Swift. The Windows x64 and ARM64 builds share the same .NET host, WebView2 editor and fonts. The Linux build uses a GTK/WebKitGTK host for the same web editor. All builds package the artwork and typewriter recordings in `Sources/Inkrail/Resources`.

## Start on your Mac

The v0.1.2 build script produces one ad-hoc signed, unnotarized `Inkrail.app` with Intel (`x86_64`) and Apple silicon (`arm64`) slices. macOS runs the native slice automatically.

To build from source, you need **macOS 13 or later** and **Apple's Swift 5.9+ developer toolchain**
(Xcode 15+ or a sufficiently recent Command Line Tools installation).
No Python, Node, package service, account, API key, or paid developer account
is required to build and run locally.

1. In the v0.1.2 source tree, open the folder containing `Package.swift`.
2. Double-click **Launch.command**. It builds a native `.app` and opens it.
3. The resulting **dist/Inkrail.app** can be dragged into Applications.

Terminal alternative, from the extracted folder:

```bash
bash scripts/build-app.sh
open dist/Inkrail.app
```

If Apple's developer tools are not installed:

```bash
xcode-select --install
```

Complete the installer, then rerun the build command. If the installed tools
are too old for Swift 5.9, update them or install a current compatible Xcode.
If Xcode asks for first-launch setup or a license acceptance, finish that
inside Xcode before building again.

For development, open the folder's **Package.swift** in Xcode, select the
**Inkrail** scheme and **My Mac**, then press Run. This is a Swift package,
not a generated `.xcodeproj`; Xcode supports opening the package directly.
`swift run Inkrail` is another development option, but the built `.app` is
preferred for normal Dock and application-menu behavior.

## Build the Windows ZIPs

Install the .NET 10 SDK and Python 3.9 or later. From the repository root, run these commands in PowerShell. Each host uses its own publish directory so files from the two architectures stay separate.

```powershell
foreach ($arch in 'x64', 'arm64') {
    dotnet publish packaging/windows/host/Inkrail.csproj -c Release -r "win-$arch" --self-contained true -o ".build/host-$arch"
    if ($LASTEXITCODE -ne 0) { throw "Host build failed for $arch" }
    python packaging/windows/build-zip.py --arch $arch --host-dir ".build/host-$arch" --output "dist/Inkrail-Windows-$arch.zip"
    if ($LASTEXITCODE -ne 0) { throw "ZIP build failed for $arch" }
}
```

Both ZIPs contain `Inkrail.exe`, its .NET runtime and WebView2 loader, the complete editor and assets, license notices, `START-HERE.txt`, a SHA-256 file manifest and `Check-Inkrail.ps1`. Extract a ZIP on a matching PC with the Microsoft Edge WebView2 Evergreen Runtime installed. Run `.\Check-Inkrail.ps1` from the extracted folder to exercise the app with disposable new and legacy libraries.

## Build the Linux bundle

The Linux build reuses the web desk from `packaging/windows/ui` verbatim. A small
GTK 3 / WebKitGTK 4.1 host serves it from a loopback-only HTTP port and supplies
the native file dialogs, window lifecycle and PDF printing through the same RPC
bridge the Windows QA mode uses. No .NET, Swift or Node toolchain is needed.

Install the runtime on Arch with:

```bash
sudo pacman -S gtk3 webkit2gtk-4.1 python-gobject gstreamer gst-plugins-base gst-plugins-good xdg-utils
```

Debian/Ubuntu: `sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1 gstreamer1.0-plugins-base gstreamer1.0-plugins-good xdg-utils`

Fedora: `sudo dnf install gtk3 webkit2gtk4.1 python3-gobject gstreamer1.0-plugins-base gstreamer1.0-plugins-good xdg-utils`

From the source root, run:

```bash
bash Launch-Linux.sh
# or build a portable folder and optional tarball:
python3 packaging/linux/build-linux.py --output dist/Inkrail-Linux.tar.gz
```

The bundle lands in `dist/Inkrail-Linux-<machine>/`. It contains the launcher,
host package, complete desk, fonts, artwork, sounds, a `.desktop` entry, app
icon and a SHA-256 manifest. Verify it with
`python3 packaging/linux/build-linux.py --check --bundle dist/Inkrail-Linux-<machine>/`.
`bash packaging/linux/install.sh --bundle <bundle>` installs it under
`~/.local/share/inkrail` with a `~/.local/bin/inkrail` link and a user desktop
entry; add `--install-deps` to install missing system packages first.

The Linux profile is `$XDG_DATA_HOME/inkrail` (normally `~/.local/share/inkrail`)
and uses the exact same preferences and letter JSON files as the Mac and Windows
apps. `python3 scripts/check-linux-host.py` exercises the RPC bridge, storage,
trash, relocation and static desk without needing a display.

## Run the tests

From the v0.1.2 source root on macOS, run `swift test` for the core models,
preferences and storage. Run `bash scripts/check-storage-model.sh` for autosave,
recovery and native editing. Run `bash scripts/check-letter-pdf.sh` to check
line wrapping, pagination and seal placement in the native PDF renderer.
On Windows, run `dotnet run --project packaging/windows/tests/StorageChecks.csproj --configuration Release`
to check the library and upgrade paths.

## GitHub release files

The **Build and release Inkrail** workflow builds and verifies the desktop archives for v0.1.2.

| Release asset | Target |
| --- | --- |
| `Inkrail.zip` | Intel and Apple silicon Macs running macOS 13 Ventura or later |
| `Inkrail-Windows-x64.zip` | Windows on Intel or AMD x64 |
| `Inkrail-Windows-arm64.zip` | Windows on ARM64 |
| `Inkrail-Linux.tar.gz` | Linux x86_64 with GTK 3 and WebKitGTK 4.1 |

Pull requests and branch pushes produce downloadable workflow artifacts. To publish, push a `v`-prefixed tag on the release commit, for example `git tag v0.2.0` followed by `git push origin v0.2.0`. Once the native checks and archive verification pass, the workflow attaches all three ZIPs directly to that tag’s GitHub Release. It creates the release if needed. Re-running the workflow for the same tag replaces its three ZIP assets.

The **Build Inkrail MSIX** workflow separately creates a Microsoft Store package from an x64 release ZIP. It verifies the file manifest and also applies the editor and sound updates when packaging the older Go-based Windows ZIP. The Store manifest requests `unvirtualizedResources` so letters under AppData survive uninstall. Include that purpose when submitting the restricted capability to Partner Center.

To exercise the Store upgrade on Windows, create letters in the default and a
custom library with the old package in a disposable Windows account. Install
the updated package over it using the same identity and open Inkrail once.
Check the letters after the upgrade, then uninstall and verify their contents
directly in both library folders.

## Make it yours

Open **Make it yours** with **⌘,** on Mac or **Ctrl+,** on Windows. Settings are arranged in seven tabs.

| Tab | Choices |
| --- | --- |
| Paper | Sheet or Paper roll, paper colour, texture and detail, embossing and relief, margin style, starting position and margin width |
| Type | Eight typefaces, type size, ribbon colour, ink darkness, worn ribbon and ink buildup |
| Machine | Twelve capsule styles, Classic capsule colours and rail finishes |
| Desk | Six finishes, paired desk lamps or small decorative objects, Leather study/Walnut study/Warm oak scenes, and wider paper in Focus Mode |
| Sound | Classic, Soft, Royal, Vintage, Portable or Electric, plus mute, volume and a preview button |
| Light | Night writing, lamp intensity and warmth, with a live preview |
| Storage | Current letters folder, Show in Finder or File Explorer, and Change Location to a new or empty folder |

Paper textures are **Classic**, **Smooth**, **Laid** and **Cotton**. Use
**Texture detail** to adjust the surface where applicable. Embossing offers
**None**, **Botanical**, **Monogram**, **Sunburst** and **Maker’s mark**, with a **Relief** control.
**Margin style** offers **None**, **Botanical**, **Ledger**, **Art Deco** and **Celestial**.
Use **Wide margins** to adjust the writing area independently of the decoration.

The desk, app icons and website share the lettering in [inkrail-mark.svg](assets/inkrail-mark.svg).
After editing the lettering or keytop artwork, run `python3 scripts/generate-logo.py` with
ImageMagick 7, Pillow and NumPy installed to update the bundled PNGs, GitHub Pages app icon,
and Windows icon.

The typefaces are **Courier**, **American Typewriter**, **Menlo**, **Georgia**,
**Courier New**, **Typewriter Light**, **Typewriter Condensed** and **Monaco**.
The Mac app uses American Typewriter's Light and Condensed faces when installed.
Windows bundles Courier Prime for the Courier choice. Both apps use local fallbacks
when a face is unavailable. For example, Windows can use Consolas for Menlo or
Lucida Console for Monaco. The editor, placeholder and previews use the same
selected face. A PDF uses the current writing width, type, ink and paper.
Embossing and decorative margins appear on the first sheet. A wax seal appears
after the last line on the final sheet. A plain-text export includes the seal
inscription. Markdown preserves its inscription, shape and color for reimport.

For an uneven old-typewriter impression, open **Type → Ribbon & ink**, enable
**Worn ribbon** and raise **Ink buildup**. Some letters gain extra weight and
darker pooled ink, while others strike lightly, with small registration shifts.
The Type tab's live sample uses the same native ink renderer as the editor.
At 0% buildup, only light pressure/registration variation remains; turn Worn
ribbon off for even native text. Ink buildup defaults to 55%, and an existing
Worn ribbon off setting stays off. Patterns are deterministic, so the ink does
not flicker when redrawn. The treatment changes drawing only, keeping native
text advances, selection and editing. Complex graphemes, ligatures, emoji and
active composition retain native rendering.

Each machine has three individually recorded keystrokes, a space bar, a
backspace, a margin bell and a carriage return. Classic uses a Hermes
Precisa 305, Soft a damped Hermes 3000, Royal a Quiet De Luxe, Vintage a
1930s manual, Portable a Hermes Baby and Electric an IBM Selectric II.
The app ships 27 edited recording excerpts and 15 sounds designed for
actions missing from the recordings. All 42 play offline. [Recording credits](../Sources/Inkrail/Resources/Sound-Credits.txt)

The bell rings as a keystroke
crosses the warning point, about seven character widths from the margin.
With proportional fonts, the exact number of letters that fit depends on
their widths. The carriage slides and hits its stop on Return or a soft wrap.
**Preview sound** plays the keys, space bar, bell and return at the selected volume.
Mute stops playback.

Saved Office and Crisp selections open as Royal and Vintage respectively.
On a fresh v0.1.2 install, the ivory paper uses **Classic** texture at **70%**
detail and **Maker’s mark** at **70%** relief, with **Margin style** set to
**None**. The slider is **Walnut** with a matching
**Brass** rail. **Classic** sounds start at **55%** volume. Turning on night
writing lights the lamp at **85%** intensity and **55%** warmth. The default
writing font is **Courier** on Mac and **Courier Prime** on Windows.

## Desk finishes and wider Focus Mode

Open **Make it yours (⌘,) → Desk** and choose **Leather study** for a warm
leather surface and paired bronze lamps, **Walnut study** for satin walnut
with the same lamps, or **Warm oak** for honey oak and two linen-shaded lamps.
The scene buttons change only the desk
finish and objects; your paper, embossing, roll, ink and lamp settings stay intact.

You can also mix **Charcoal**, **Walnut**, **Felt**, **Linen**, **Honey Oak** or
**Leather** with **Paired bronze lamps**, **Paired linen lamps**, **Botanical sprig**,
**Paperclip**, **Envelope** or **None**. The wooden surfaces use muted,
interrupted fibres and pores rather than repeating waves. Leather has an
original cached height-field texture with fine creases and surface shading.
The lamps use original three-dimensional models with bronze reflections or
woven linen, rendered locally into transparent artwork. The development-only
generator is `scripts/render-desk-lamps.sh`; no 3D engine runs in the app.
Small objects use folded paper, subtle metal glints and individually shaped leaves.

The paired lamps cast broad, soft pools onto the material and grazing light
along both paper edges, using the same warmth/intensity mapping as the capsule.
One layout anchors the modeled shade, emitter, desk pool and paper highlight.
Light fades within the outer 42 points, before the narrowest writing inset;
paper geometry, embossing and native text remain intact. Night writing reveals
paper grain inside that same edge field. This is a coordinated lighting
approximation, not a real-time physical simulation.

The default remains the original charcoal desk with no objects. These are
original procedural surfaces, locally rendered lamp artwork and small vector
objects, with no downloaded assets, random-on-redraw textures or animation
timers. Lamp bodies stay outside the paper; their light can reach its margins.
Objects and their light tuck away in narrow windows. A live settings preview uses
the same desk and paper components.

**Focus Mode (⇧⌘F)** widens the sheet from 720 to at most 960 points when the
window has room. At the default 1080-point window, 60-point borders remain on
both sides. **Desk → Wider paper in Focus Mode** can restore the original
width. Small windows retain the existing 52-point side inset.

The actual editor reflows at the new width; font size, inner margins, paper
height, embossing size and vertical roll geometry stay the same. The curved
shoulders continue to follow the paper width. Width changes in one native
layout step, avoiding stretched artwork or
repeated animated text wrapping. Focus temporarily uses the quiet charcoal
background with no desk accents. Leaving Focus restores the selected finish,
accent and regular sheet width. Paper, ink, lamp and sound preferences remain
independent; all decoration stays outside the editable text system.

## Paper roll

Open **Make it yours (⌘,) → Paper → Page layout → Paper motion → Paper roll**.
**Start writing → Top or Bottom** remains available for both paper modes.
Top begins near the upper margin, advances downward, and feeds once the lower
writing band is reached. Bottom starts at the lower writing band and feeds
from the first new line. Lines feed in a short eased movement, and older lines flatten and
narrow as they pass over the stationary curved upper edge. Texture and
embossing use the same paper curve. The capsule returns quickly to the next
line. Reduce Motion makes the feed and carriage movement immediate.

**Paper roll** and **Bottom** are the defaults. Switching paper
motion keeps the chosen starting position. **Curved upper corners** now uses
longer tapered shoulders, a shallow bowed lip and softer light across the
paper's bend. Turn it off to retain the simple rectangular edge.

## Automatic paper feed and starting position

Open **Make it yours** with **Command-comma (⌘,)**, then choose
**Paper → Page layout → Start writing → Top or Bottom** in either paper mode.

- **Top** starts near the top of the paper. Lines advance downward until
  they reach the lower writing band, then the paper feeds upward automatically
  as you continue writing.
- **Bottom** starts near the lower part of the paper. As you type or delete
  lines, the text feeds upward or back down to keep the insertion line near
  the lower writing band, with the capsule and rail below it.

You can still scroll to read and select earlier text. Resuming typing brings
the active line into view; Bottom places it at the writing band. The grain,
embossing and upper paper edge move with the native scroll position. This
setting applies to the desk; switching it changes layout, not the content or
order of your letters. It
does not insert blank lines into saved notes or exports.

## Slider styles

Open **Make it yours** with **Command-comma**, then **Machine → Slider styles**.
There are twelve designs for the moving typewriter capsule and rail. The six
original styles remain, alongside six new material and decorative choices:

| Style | Material treatment |
| --- | --- |
| Classic | Original capsule and its five colour swatches |
| Brushed Steel | Satin metal, rounded rectangular body, machined grip ribs |
| Champagne | Muted gold, Art Deco lines, inset diamond badge |
| Walnut | Procedural wood grain, brass nameplate and small screw heads |
| Porcelain | Rounded ivory ceramic, subtle speckling, sage inset |
| Midnight | Graphite housing, fine gold outline and monogram |
| Rose Quartz | Blush pearlescent finish |
| Sea Glass | Frosted teal with cool highlights |
| Lavender | Soft lilac enamel |
| Racing Green | Deep green with brass detailing |
| Copper | Warm hammered metal |
| Wildflower | Cream enamel with original floral decoration |

Tiles and previews reuse the actual desk components. Pick a style to apply it;
no restart or Apply button is needed. New styles use a coordinated rail by
default. Disable **Match rail to style** to choose Steel, Brass or Charcoal.
Your old Classic capsule colour and manual rail selection are kept separately;
returning to Classic restores those choices. Paper, ribbon, sound and the
night lamp's warmth/intensity are not changed by style selection.
