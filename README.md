<div align="center">
  <img src="Sources/Inkrail/Resources/AppIcon.png" width="88" alt="Inkrail icon" />
  <h1>Inkrail</h1>
  <p><em>Paper, ink, and a little room to write.</em></p>
  <p>A quiet, offline writing desk for Mac and Windows. No accounts or subscriptions.</p>
  <p><a href="https://github.com/Aaryanverma/inkrail/releases">Mac and Windows downloads</a> · <a href="https://apps.microsoft.com/detail/9nq2fds73hpz">Get it for Windows on the Microsoft Store</a></p>
</div>

🎥 Watch the macOS demo ↓
<p align="center">
  <a href="https://youtu.be/oanl6tyIvMo">
    <img src="screenshots/inkrail-light-mode.png" alt="Watch the Inkrail macOS demo" width="760">
  </a>
</p>

<details>
  <summary>📸 View macOS screenshots</summary>

| Light mode | Night writing |
| --- | --- |
| ![A welcome note on ivory paper, with a leafy sprig to the left of the sheet](screenshots/inkrail-light-mode.png) | ![The same note on dark paper, lit just above the walnut carriage](screenshots/inkrail-night-mode.png) |

| Night desk | Focus Mode |
| --- | --- |
| ![Two bronze lamps flank the dark sheet on a walnut desk](screenshots/inkrail-night-desk.png) | ![A wider ivory sheet and walnut carriage with the desk objects and footer controls hidden](screenshots/inkrail-focus-mode.png) |

| Botanical margins | Paper embossings |
| --- | --- |
| ![Green sprigs and purple buds border both sides of the welcome note](screenshots/inkrail-paper-margin-options.png) | ![Botanical, Monogram, Sunburst and Maker’s mark at 45% relief in day and night light](screenshots/inkrail-paper-embossings.png) |

| Seal options | Sealed letter |
| --- | --- |
| ![The Seal letter dialog previews the initials AV in red wax over a sheet with botanical margins](screenshots/inkrail-seal-options.png) | ![A red AV seal sits below “Always yours.” on the finished letter](screenshots/inkrail-seal-preview.png) |

| Machine styles | Maker’s mark |
| --- | --- |
| ![Twelve carriage finishes with Walnut selected](screenshots/inkrail-machine-customizations.png) | ![An embossed IR mark in the upper corner of a letter framed by two desk lamps](screenshots/inkrail-makers-mark.png) |

| Desk settings | Lighting settings |
| --- | --- |
| ![The Walnut study preset with paired bronze lamps in the desk preview](screenshots/inkrail-desk-customizations.png) | ![Night writing preview with sliders for lamp intensity and warmth](screenshots/inkrail-light-customizations.png) |

| Sound settings | Storage options |
| --- | --- |
| ![Six typewriter sound presets with volume and preview controls](screenshots/inkrail-sound-customizations.png) | ![The letters folder with controls to change its location or show it in Finder](screenshots/inkrail-storage-options.png) |

</details>

## Make yourself at home

Textured paper. A small moving typewriter. Warm lamps and optional mechanical
sounds. Open **Make it yours** to choose your paper, typeface, ink and desk.
On a fresh desk, the Walnut carriage runs on a brass rail. The ivory paper roll uses Classic texture at 70% detail and **Maker’s mark**, the carriage’s initials pressed into the sheet at 70% relief.
You can change the mark or its relief under **Paper → Embossing**.
Under **Paper → Paper surface → Margin style**, choose Botanical sprigs, Ledger rules, Art Deco diamonds
or Celestial constellations. Choose **None** for a plain edge.
**Focus Mode** clears the desk decorations. When the window has room, **Desk → Wider paper in Focus Mode** also widens the sheet.
In **Top** mode, the capsule and rail move below the visible writing when you
edit an earlier paragraph.

## Install

### macOS

Inkrail v0.1.2 runs natively on Intel and Apple silicon Macs with **macOS 13 Ventura or later**. Choose the universal `Inkrail.zip` from the [GitHub releases](https://github.com/Aaryanverma/inkrail/releases), unzip it, and drag **Inkrail.app** into **Applications**.
To check the architecture, select the app in Finder and press **⌘I**. Finder shows **Application (Universal)** under **Kind**.

macOS may block this unnotarized build the first time you open it.

- In Applications, Control-click (or right-click) **Inkrail.app**, choose
**Open**, then choose **Open** again in the confirmation dialog. You only need
to do this the first time.
- If macOS does not offer that option, try opening the
app once, then go to **System Settings → Privacy & Security** and choose
**Open Anyway** for Inkrail.

### Windows

Get Inkrail from the [Microsoft Store](https://apps.microsoft.com/detail/9nq2fds73hpz) or choose a portable ZIP from the [GitHub releases](https://github.com/Aaryanverma/inkrail/releases). Check **Settings → System → About → System type** to find your PC’s architecture.

| PC processor | Portable ZIP |
| --- | --- |
| Intel or AMD x64 | `Inkrail-Windows-x64.zip` |
| ARM64, including Snapdragon | `Inkrail-Windows-arm64.zip` |

Choose **Extract All** and open **Inkrail.exe** in the extracted folder. Keep the folder together if you move the app.
If Inkrail asks for the Microsoft Edge WebView2 Evergreen Runtime, install it and reopen the app. [Get WebView2 from Microsoft](https://developer.microsoft.com/microsoft-edge/webview2/)

## Build from source

For Windows x64 and ARM64, follow the [Windows build instructions](docs/DEVELOPMENT.md#build-the-windows-zips).

To build the Mac app on macOS 13 or later with Apple's Swift 5.9+ developer tools, double-click **Launch.command** or run the following commands.

```bash
bash scripts/build-app.sh
open dist/Inkrail.app
```

See [macOS setup & troubleshooting](docs/DEVELOPMENT.md#start-on-your-mac).

## At your desk

| Action | Mac | Windows |
| :--- | :--- | :--- |
| New letter | ⌘N | Ctrl+N |
| Bold / Italic / Underline | ⌘B / ⌘I / ⌘U | Ctrl+B / Ctrl+I / Ctrl+U |
| Clear inline formatting | `⌘\` | `Ctrl+\` |
| Letter box | ⇧⌘O | Ctrl+Shift+O |
| Make it yours | ⌘, | Ctrl+, |
| Focus Mode | ⇧⌘F | Ctrl+Shift+F |
| Night writing | ⌥⌘L | Ctrl+Alt+L |
| Sound on / off | ⇧⌘M | Ctrl+Shift+M |
| Import text or Markdown | ⌘O | Ctrl+O |
| Export text | ⇧⌘E | Ctrl+Shift+E |
| Save now | ⌘S | Ctrl+S |

Use the **B**, *I*, and underline buttons at the foot of the paper to format a
selection or the words you type next. Each letter remembers its emphasis and
uses the typeface you choose in **Make it yours**. Copying between letters
preserves inline formatting. Pasting rich text from another app can also
preserve bold, italic, underline and strikethrough.

The top of the desk shows the character count. The footer shows the word count
and save status as you type. Writing saves automatically. If a save fails,
export a copy before closing.

Markdown shortcuts work as you type. Use `*italic*`, `**bold**`, or
`***bold italic***`. Underscores work in the same patterns. Use
`~~strikethrough~~` or wrap inline code in backticks. To keep a multiline
example literal, surround it with matching lines of three backticks or tildes.

Start a paragraph with one to six hashes and a space for a heading. In
`# Hi`, typing the `H` hides the heading marker. For a quote, use `>`
and a space. For a list, use `-`, `*`, `+`, or a number followed by
`.` or `)`, then a space. Quote and list markers stay visible.
Markdown export keeps all three kinds of paragraph marker.

### Sealing and exporting

After writing, choose **Seal letter…** at the foot of the page. Enter an inscription
(up to 24 characters), pick a shape and wax color, then choose **Apply seal**.
Use **Edit seal…** to change or remove it.

Use the export button on the paper to choose a format.

- **Export Letter as PDF…** preserves the stationery, formatting, and any wax seal for printing.
- **Export Interactive Letter** creates a sealed envelope using your seal or one you choose for the export.
  Send the HTML file. Your reader can save it, open it in a browser, and tap or click the seal to unfold the letter, even offline.
  For privacy, select **Require a password** and share the passphrase separately. If you forget it, export the original again with a new passphrase.
- **Export Markdown…** keeps the formatting and seal so you can import the letter on another Mac or Windows PC.
- **Export Text…** saves a plain-text copy.

## Your letters

Open the letter box to search by private title or any words in a letter.
Search works in both the active letter box and **Recently deleted**. Each view
groups letters by the month you last edited them, newest first. Inkrail reopens
the letter you last selected.

To give a letter a private title, right-click it on Mac and choose **Rename…**.
On Windows, use its pencil icon, right-click the letter, or press **F2** while
the letter has keyboard focus. Clear the title to use the opening line again.
Text and Markdown exports include the letter body and any seal inscription.
Importing the Markdown copy into Inkrail also restores the seal’s shape and
color. The suggested filename comes from the letter’s opening line.

Inkrail saves letters locally. You can open the current library from within the app.

| Platform | Default library folder | Open the folder |
| :--- | :--- | :--- |
| macOS | `~/Library/Application Support/Inkrail/` | **Writing → Show Local Files** |
| Windows | `%APPDATA%\Inkrail\Library` | **Make it yours → Storage → Show in File Explorer** |

- To **move your library**, open **Make it yours → Storage → Change Location…** and
  choose a new or empty folder. Inkrail copies the whole library there and keeps the old copy.
- To **restore a deleted letter**, open the letter box and choose
  **Recently deleted → Restore** within **30 days**. After that window,
  Inkrail removes the deleted letter when it next checks.

Keep a separate backup of your library. [Storage & recovery on Mac and Windows →](docs/STORAGE.md)

## Inspiration

<p>Highly inspired by <a href="https://apps.apple.com/in/app/platen-paper-ink/id6809529696">Platen — Paper &amp; Ink</a> app by Rafikki Studio for iOS.<br />

> At the time of making of Inkrail, Platen app was not built/available for macOS & Windows, so Inkrail fills that gap with extra features that too completely free. Not sponsored by Platen.

---

<div align="center">
  <p>Made with ❤︎ by <strong><a href='https://linkedin.com/in/aaryanverma' target='_blank'>Aaryan Verma</a></strong></p>
  An independent project.</p>
  <p><a href="https://aaryanverma.github.io/inkrail/">Inkrail website</a> · <a href="LICENSE">MIT License</a> · <a href="docs/DEVELOPMENT.md">Development</a></p>
</div>
