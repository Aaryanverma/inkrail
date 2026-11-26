import AppKit
import SwiftUI
import InkrailCore

// Inert boundary dependencies: production WritingDesk/PaperStage and all their
// visible subviews compile unchanged, while persistence, sound and unused
// sheets are deliberately absent from this isolated native rendering check.
enum StrokeKind { case key, space, carriage, erase, navigation, bell }
@MainActor final class SoundEngine {
    static let shared = SoundEngine()
    func play(_ kind: StrokeKind, volume: Double, style: TypewriterSound) {}
}
extension Notification.Name {
    static let inkrailFocusEditor = Notification.Name("Inkrail.FocusEditor")
}
extension Bundle {
    static let module = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("FixtureResources.bundle"))!
}
@MainActor final class AppModel: ObservableObject {
    @Published var preferences: WritingPreferences
    @Published var selectedPage: Page?
    var paperSizeForExport: CGSize?
    @Published var showLibrary = false
    @Published var showStudio = false
    @Published var sealEditorPage: Page?
    @Published var interactiveExportPage: Page?
    var canSealSelectedPage: Bool { selectedPage?.canApplySeal == true }
    @Published var focusMode = false
    @Published var errorMessage: String?
    weak var editor: (any LetterEditor)?
    var isDirty = false
    var saveState = "Isolated native render"
    init(preferences: WritingPreferences, text: String) {
        self.preferences = preferences
        self.selectedPage = Page(createdAt: Date(timeIntervalSince1970: 1794652800), text: text)
    }
    func edit(_ id: UUID, text: String, formatting: [TextFormatRun] = []) {
        guard var page = selectedPage, page.id == id else { return }
        page.text = text
        page.formatting = formatting
        selectedPage = page
    }
    func createPage() { selectedPage = Page() }
    func focusEditor() {}
    func openSealEditor() { sealEditorPage = selectedPage }
    func setSeal(_ seal: LetterSeal?, for id: UUID) {
        if selectedPage?.id == id { selectedPage?.seal = seal }
    }
    func export(markdown: Bool = false) {}
    func exportPDF() {}
    func exportInteractiveLetter() {}
    func saveInteractiveLetter(_ page: Page, seal: LetterSeal, password: String?) {}
}
struct LetterBox: View { var body: some View { EmptyView() } }
struct StudioView: View { var body: some View { EmptyView() } }
private struct CheckFailure: Error, CustomStringConvertible { let description: String }

@main @MainActor private enum WritingDeskCheck {
    static var failures: [String] = []
    static var focusChecks = 0
    static var referencePatches: [String: [Double]] = [:]
    static let patchOffsets = [CGPoint(x: -30, y: 5), CGPoint(x: 27, y: 5), CGPoint(x: 27, y: -5)]
    static let output = URL(fileURLWithPath: CommandLine.arguments[1])
    static let longText = (1...28).map { "Line \($0): The paper carries another quiet thought." }.joined(separator: "\n")
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        if CommandLine.arguments.contains("--top-editing-only") {
            for motion in [PaperMotion.sheet, .roll] {
                for lines in [12, 48] { try checkTopRevision(motion: motion, lines: lines) }
            }
            print("PASS Top revision and end-of-letter checks in Sheet and Roll, with short and overflowing letters.")
            return
        }
        if CommandLine.arguments.contains("--desk-material-diagnostic") {
            try renderPaperBlendDiagnostic()
            return
        }
        if CommandLine.arguments.contains("--strike-only") {
            try renderPeakStrike()
            return
        }
        if CommandLine.arguments.contains("--desk-lamp-colour-only") {
            try checkPairedLampColour()
            return
        }
        if CommandLine.arguments.contains("--emboss-only") {
            try renderEmbossingInvariant()
            print("PASS \(focusChecks) embossing pixel-size assertions at normal and Focus widths.")
            return
        }
        if CommandLine.arguments.contains("--desk-lamps-only") || CommandLine.arguments.contains("--desk-grazing-only") {
            if !CommandLine.arguments.contains("--desk-grazing-only") { try renderDeskIsolation() }
            try renderPairedLamps()
            if !failures.isEmpty {
                failures.forEach { print("FAIL \($0)") }
                exit(1)
            }
            print("PASS \(focusChecks) desk-lamp assertions plus production housing/rail checks; isolated native views, not live screenshots.")
            return
        }
        if CommandLine.arguments.contains("--desk-isolation-only") {
            try renderDeskIsolation()
            if !failures.isEmpty {
                failures.forEach { print("FAIL \($0)") }
                exit(1)
            }
            print("PASS \(focusChecks) desk isolation assertions plus production housing/rail checks; isolated native views.")
            return
        }
        if CommandLine.arguments.contains("--desk-reference-only") {
            var preferences = WritingPreferences()
            preferences.paperMotion = .roll
            preferences.paperStartPosition = .bottom
            preferences.paperTexture = .cotton
            preferences.paperEmbossing = .botanical
            preferences.embossingDepth = 0.85
            preferences.deskFinish = .leather
            preferences.deskAccent = .brassLamps
            preferences.soundEnabled = false
            try render(preferences, size: CGSize(width: 1733, height: 908),
                       text: "A quiet edge of light.\nPaper, brass and native words.",
                       name: "desk-leather-reference-wide", defaultSizing: false)
            print("Rendered the 1733x908 reference desk for visual review; grazing-light assertions were not run in this preview mode.")
            return
        }
        if CommandLine.arguments.contains("--focus-only") {
            try renderFocusAndDesk()
            if !failures.isEmpty {
                failures.forEach { print("FAIL \($0)") }
                exit(1)
            }
            print("PASS \(focusChecks) focus/desk assertions plus production housing/rail pixel checks; unshown native windows, not live app screenshots.")
            return
        }
        var preferences = WritingPreferences()
        preferences.paperMotion = .roll
        preferences.paperStartPosition = .bottom
        preferences.mechanismStyle = .classic
        preferences.capsule = .porcelain
        preferences.rail = .steel
        preferences.nightMode = false
        preferences.curvedPaper = true
        preferences.fontSize = 20
        preferences.wideMargins = false
        preferences.soundEnabled = false
        let size = CGSize(width: 1224, height: 784)
        try render(preferences, size: size, text: "", name: "saved-empty-default-sizing", defaultSizing: true)
        try render(preferences, size: size, text: "A quiet page.\nA place to begin.", name: "saved-short-default-sizing", defaultSizing: true)
        try render(preferences, size: size, text: longText, name: "saved-long-default-sizing", defaultSizing: true)
        try render(preferences, size: size, text: longText, name: "saved-long-fixed-sizing", defaultSizing: false, transitions: true)
        try render(preferences, size: CGSize(width: 1080, height: 820), text: longText, name: "standard-long", defaultSizing: true)
        try render(preferences, size: CGSize(width: 660, height: 580), text: "", name: "minimum-empty", defaultSizing: true)
        try renderMatrix(preferences, size: size)
        try renderFocusAndDesk()
        try renderPairedLamps()
        try checkPairedLampColour()
        try renderEmbossingInvariant()
        try renderPeakStrike()
        if !failures.isEmpty {
            failures.forEach { print("FAIL \($0)") }
            exit(1)
        }
        print("PASS production WritingDesk native renders and housing/rail pixel checks; unshown windows, inert model, not running-app screenshots.")
    }
    static func checkTopRevision(motion: PaperMotion, lines: Int) throws {
        let name = "top-revision-\(motion.rawValue)-\(lines)"
        let body = (1...lines).map { "Line \($0) has words across the page." }.joined(separator: "\n")
        var preferences = WritingPreferences()
        preferences.paperStartPosition = .top
        preferences.paperMotion = motion
        let model = AppModel(preferences: preferences, text: body)
        let size = CGSize(width: 1080, height: 820)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: WritingDesk().environmentObject(model))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        settle(host)
        guard let editor = descendant(InkTextView.self, in: host),
              let clip = editor.enclosingScrollView?.contentView else {
            throw CheckFailure(description: "\(name): missing editor")
        }
        func textRect(_ range: NSRange) -> CGRect {
            let screen = editor.firstRect(forCharacterRange: range, actualRange: nil)
            return host.convert(window.convertFromScreen(screen), from: nil)
        }
        func capsuleRect() throws -> CGRect {
            guard let capsule = capsuleFocusView(in: host) else { throw CheckFailure(description: "\(name): missing capsule") }
            return capsule.convert(capsule.bounds, to: host)
        }
        window.makeFirstResponder(editor)
        let location = NSMaxRange((body as NSString).range(of: "Line 4 has "))
        editor.setSelectedRange(NSRange(location: location, length: 0))
        editor.insertText("more ", replacementRange: editor.selectedRange())
        settle(host)
        let viewport = clip.convert(clip.bounds, to: host)
        let caret = textRect(editor.selectedRange())
        try require(caret.minY >= viewport.minY - 1 && caret.maxY <= viewport.maxY + 1,
                    "\(name): revision caret is outside the viewport")
        let nextLine = (editor.string as NSString).range(of: "Line 5")
        try require(viewport.contains(textRect(nextLine)), "\(name): next line is outside the viewport")
        // These short paragraphs each occupy one native line. The hammer is
        // the highest part of the mechanism and sits within 2 pt of its frame top.
        let hammerTop = try capsuleRect().minY + 2
        let source = editor.string as NSString
        for line in 5...lines {
            let rect = textRect(source.range(of: "Line \(line) "))
            let visibleLine = rect.intersection(viewport)
            if !visibleLine.isEmpty {
                try require(visibleLine.maxY <= hammerTop + 1,
                            "\(name): line \(line) extends to \(visibleLine.maxY), mechanism begins at \(hammerTop)")
            }
        }
        try capture(host, model: model, name: name, size: size)
        try require(failures.isEmpty, "\(name): \(failures.joined(separator: ", "))")

        editor.setSelectedRange(NSRange(location: source.length, length: 0))
        editor.insertText("!", replacementRange: editor.selectedRange())
        settle(host)
        let endCaret = textRect(editor.selectedRange())
        let capsule = try capsuleRect()
        try require(abs(capsule.midX - endCaret.minX) <= 2 && abs(capsule.midY - endCaret.maxY - 42) <= 2,
                    "\(name): capsule did not return to the normal typing position")
    }

    static func renderPeakStrike() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw CheckFailure(description: "Peak-strike overflow check requires Reduce Motion off; system setting was preserved")
        }
        let size = CGSize(width: 300, height: 200)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView:
            CapsuleView(finish: .porcelain, striking: true)
                .frame(width: size.width, height: size.height)
                .background(DeskPalette.paper)
                .transaction { $0.disablesAnimations = true; $0.animation = nil })
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        settle(host, duration: 0.1)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 200,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("capsule-peak-strike.png"))
        // The fixed 116×100 frame starts at y=50. Peak strike raises the
        // hammer to y=47.5; its dark row above y=50 must survive compositing.
        let hammerPixels = (140...159).filter { x in
            guard let color = bitmap.colorAt(x: x, y: 48)?.usingColorSpace(.deviceRGB) else { return false }
            return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent < 0.7
        }.count
        let shadow = meanLuminance(bitmap, x: 150, y: 131)
        let paper = meanLuminance(bitmap, x: 210, y: 131)
        guard hammerPixels >= 18, shadow < paper - 0.05 else {
            throw CheckFailure(description: "Peak strike clipped: hammer pixels=\(hammerPixels), shadow=\(shadow), paper=\(paper)")
        }
        let metadata: [String: Any] = ["kind": "isolated CapsuleView peak strike render",
            "fixedFrameTopY": 50, "hammerSampleY": 48, "visibleHammerPixelsAboveFrame": hammerPixels,
            "shadowLuminance": shadow, "paperLuminance": paper,
            "animationsDisabled": true, "reduceMotion": false]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("capsule-peak-strike.json"))
        print("PASS peak strike: \(hammerPixels) hammer pixels above fixed frame and visible housing shadow")
    }
    static func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews { if let match = descendant(type, in: child) { return match } }
        return nil
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        focusChecks += 1
        guard condition() else { throw CheckFailure(description: message) }
    }

    static func bitmap(_ host: NSView, size: CGSize) throws -> NSBitmapImageRep {
        guard let result = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CheckFailure(description: "Focus bitmap allocation failed")
        }
        result.size = size
        host.cacheDisplay(in: host.bounds, to: result)
        return result
    }

    static func difference(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep, in rect: CGRect) -> Double {
        var error = 0.0
        var count = 0
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 3) {
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 3) {
                guard let a = first.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let b = second.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                error += abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                    + abs(a.blueComponent - b.blueComponent)
                count += 3
            }
        }
        return count == 0 ? 1 : error / Double(count)
    }

    static func lampColour(_ image: NSBitmapImageRep, in rect: CGRect) -> (luminance: Double, warmth: Double) {
        var luminance = 0.0, warmth = 0.0
        var count = 0
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 3) {
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 3) {
                guard let colour = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                luminance += 0.2126 * colour.redComponent + 0.7152 * colour.greenComponent + 0.0722 * colour.blueComponent
                warmth += colour.redComponent - colour.blueComponent
                count += 1
            }
        }
        return count == 0 ? (0, 0) : (luminance / Double(count), warmth / Double(count))
    }

    /// Compare broad, mirror-paired regions rather than requiring the desk's
    /// original material grain to be mirror-identical. These are the actual
    /// composited production colours, not just the shared LampAppearance RGB.
    static func pairedColour(_ image: NSBitmapImageRep, in rect: CGRect) -> (left: [Double], right: [Double]) {
        var left = [Double](repeating: 0, count: 3)
        var right = left
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                guard let a = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let b = image.colorAt(x: image.pixelsWide - 1 - x, y: y)?.usingColorSpace(.sRGB) else { continue }
                for (channel, value) in [a.redComponent, a.greenComponent, a.blueComponent].enumerated() {
                    left[channel] += value
                }
                for (channel, value) in [b.redComponent, b.greenComponent, b.blueComponent].enumerated() {
                    right[channel] += value
                }
                count += 1
            }
        }
        return (left.map { $0 / Double(max(1, count)) }, right.map { $0 / Double(max(1, count)) })
    }

    static func checkPairedLampColour() throws {
        let defaults = WritingPreferences.defaults
        let size = CGSize(width: 1080, height: 820)
        let paperWidth = DeskLayout.paperWidth(windowWidth: size.width, focusMode: false, widerFocusPaper: true)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: DeskBackdrop(finish: .leather, accent: .brassLamps,
            paperWidth: paperWidth, focusMode: false, nightMode: false))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        var records = [[String: Any]]()
        var mismatches = [String]()
        for finish in DeskFinish.allCases {
            for accent in [DeskAccent.brassLamps, .linenLamps] {
                let scene = DeskSceneLayout(windowWidth: size.width, windowHeight: size.height,
                                            paperWidth: paperWidth, accent: accent)
                let s = scene.lampScale
                let regions = [
                    ("emitter", CGRect(x: scene.leftEmitterX - 12 * s, y: scene.emitterY - 3 * s,
                                       width: 24 * s, height: 6 * s)),
                    ("pool", CGRect(x: scene.leftEmitterX + 2 * s, y: scene.emitterY + 65 * s,
                                    width: 56 * s, height: 70 * s))
                ]
                for night in [false, true] {
                    for warmth in [0.0, defaults.lampWarmth, 1.0] {
                        host.rootView = DeskBackdrop(finish: finish, accent: accent, paperWidth: paperWidth,
                            focusMode: false, nightMode: night, lampWarmth: warmth, lampIntensity: defaults.lampIntensity)
                        settle(host, duration: 0.04)
                        let image = try bitmap(host, size: size)
                        let name = "\(finish.rawValue)/\(accent.rawValue)/\(night ? "night" : "day")/\(warmth)"
                        for (region, rect) in regions {
                            let colours = pairedColour(image, in: rect)
                            let delta = zip(colours.left, colours.right).map { abs($0 - $1) }.max() ?? 1
                            let luminance: ([Double]) -> Double = { 0.2126 * $0[0] + 0.7152 * $0[1] + 0.0722 * $0[2] }
                            let brightnessDelta = abs(luminance(colours.left) - luminance(colours.right))
                            let warmthDelta = abs((colours.left[0] - colours.left[2]) - (colours.right[0] - colours.right[2]))
                            // Two sRGB code values allow averaged texture and
                            // sampling variation, while catching a visibly
                            // different ambient tint/brightness under one lamp.
                            let tolerance = 2.0 / 255
                            let matches = delta <= tolerance
                            focusChecks += 1
                            if !matches {
                                mismatches.append("\(name)/\(region): RGB delta \(delta), luminance delta \(brightnessDelta), warmth delta \(warmthDelta)")
                            }
                            records.append(["scene": name, "region": region, "leftRGB": colours.left,
                                            "rightRGB": colours.right, "maxRGBDelta": delta,
                                            "luminanceDelta": brightnessDelta, "warmthDelta": warmthDelta,
                                            "tolerance": tolerance, "passed": matches])
                        }
                    }
                }
            }
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("desk-lamp-colour.json"))
        if !mismatches.isEmpty {
            mismatches.forEach { print("FAIL \($0)") }
            print("FAIL \(mismatches.count) of \(records.count) paired lamp colour checks; see desk-lamp-colour.json")
            exit(1)
        }
        print("PASS \(records.count) paired emitter/pool colour checks across six desk finishes, both lamp styles, cool/default/warm settings and day/night; isolated native views.")
    }

    static func checkFocusState(_ host: NSView, window: NSWindow, model: AppModel,
                                editor: InkTextView, size: CGSize, text: String,
                                selection: NSRange, name: String) throws {
        guard let scroll = editor.enclosingScrollView else { throw CheckFailure(description: "Missing focus scroll view") }
        let expectedWidth = DeskLayout.paperWidth(windowWidth: size.width, focusMode: model.focusMode,
                                                  widerFocusPaper: model.preferences.widerFocusPaper)
        let rect = scroll.convert(scroll.bounds, to: host)
        try require(abs(rect.width - expectedWidth) < 1, "\(name): actual paper width \(rect.width) != \(expectedWidth)")
        try require(abs(rect.midX - size.width / 2) < 1, "\(name): paper is no longer centered")
        try require(descendant(InkTextView.self, in: host) === editor,
                    "\(name): focus rebuilt the native text editor")
        try require(editor.string == text && model.selectedPage?.text == text && editor.selectedRange() == selection,
                    "\(name): focus changed text or native selection")
        let screen = editor.firstRect(forCharacterRange: NSRange(location: selection.location, length: 0), actualRange: nil)
        let clip = scroll.contentView
        let caret = clip.convert(window.convertFromScreen(screen), from: nil)
        try require(caret.minY >= clip.bounds.minY - 1 && caret.maxY <= clip.bounds.maxY + 3,
                    "\(name): selected native line left the visible viewport: \(caret), \(clip.bounds)")
        let expectedHeight = PaperFeedLayout.editorHeight(paperHeight: max(440, size.height - 112),
            position: model.preferences.paperStartPosition, motion: model.preferences.paperMotion)
        try require(abs(clip.bounds.height - expectedHeight) < 1,
                    "\(name): focus changed the vertical paper-feed geometry")
        try require((editor.layoutManager as? InkLayoutManager)?.paperRollEnabled == (model.preferences.paperMotion == .roll),
                    "\(name): focus changed native roll projection")
        try require(model.preferences.paperEmbossing == .botanical && model.preferences.embossingDepth == 0.85
                    && model.preferences.curvedPaper && model.preferences.paperTexture == .laid,
                    "\(name): focus reset the paper treatment")
        try capture(host, model: model, name: name, size: size)
    }

    static func renderFocusAndDesk() throws {
        let text = "The sheet keeps its quiet character.\n"
            + String(repeating: "Embossed paper, native words and a little room to write. ", count: 9)
        for size in [CGSize(width: 1080, height: 820), CGSize(width: 660, height: 580), CGSize(width: 1440, height: 900)] {
            for motion in [PaperMotion.sheet, .roll] {
                for start in [PaperStartPosition.top, .bottom] {
                    var preferences = WritingPreferences()
                    preferences.paperMotion = motion
                    preferences.paperStartPosition = start
                    preferences.paperTexture = .laid
                    preferences.paperEmbossing = .botanical
                    preferences.embossingDepth = 0.85
                    preferences.deskFinish = .walnut
                    preferences.deskAccent = .sprig
                    preferences.soundEnabled = false
                    let model = AppModel(preferences: preferences, text: text)
                    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isRestorable = false
                    window.isReleasedWhenClosed = false
                    defer { window.close() }
                    let host = NSHostingView(rootView: WritingDesk().environmentObject(model).preferredColorScheme(.dark))
                    host.sizingOptions = []
                    host.frame = CGRect(origin: .zero, size: size)
                    window.contentView = host
                    settle(host)
                    guard let editor = descendant(InkTextView.self, in: host) else {
                        throw CheckFailure(description: "Focus matrix editor missing")
                    }
                    // A real nonempty selection must survive the width change.
                    let selection = NSRange(location: (text as NSString).length - 24, length: 12)
                    editor.setSelectedRange(selection)
                    settle(host)
                    let prefix = "focus-\(Int(size.width))-\(motion.rawValue)-\(start.rawValue)"
                    for (label, focused) in [("normal", false), ("wide", true), ("restored", false)] {
                        model.focusMode = focused
                        settle(host)
                        try checkFocusState(host, window: window, model: model, editor: editor, size: size,
                                            text: text, selection: selection, name: "\(prefix)-\(label)")
                    }
                    if size.width == 1080 && motion == .sheet && start == .top {
                        model.preferences.widerFocusPaper = false
                        model.focusMode = true
                        settle(host)
                        try checkFocusState(host, window: window, model: model, editor: editor, size: size,
                                            text: text, selection: selection, name: "focus-width-opt-out")
                    }
                }
            }
        }
        try renderDeskIsolation()
    }

    static func renderDeskIsolation() throws {
        let size = CGSize(width: 1080, height: 820)
        var preferences = WritingPreferences()
        preferences.paperMotion = .roll
        preferences.paperTexture = .cotton
        preferences.paperEmbossing = .sunburst
        preferences.embossingDepth = 0.9
        preferences.soundEnabled = false
        let model = AppModel(preferences: preferences, text: "")
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: WritingDesk().environmentObject(model).preferredColorScheme(.dark))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        settle(host)
        let normal = try bitmap(host, size: size)
        // Grazing desk light intentionally reaches the paper's outer margin.
        // The writing field and embossing remain independent of desk choices.
        let interior = CGRect(x: 270, y: 128, width: 540, height: 550)
        let embossing = CGRect(x: 740, y: 92, width: 110, height: 112)
        let choices: [(DeskFinish, DeskAccent)] = [(.walnut, .none), (.felt, .none), (.linen, .none), (.oak, .none), (.leather, .none),
                                                 (.charcoal, .sprig), (.charcoal, .paperclip), (.charcoal, .envelope),
                                                 (.walnut, .brassLamps), (.oak, .linenLamps), (.leather, .brassLamps)]
        for (finish, accent) in choices {
            model.preferences.deskFinish = finish
            model.preferences.deskAccent = accent
            settle(host)
            let current = try bitmap(host, size: size)
            let error = difference(normal, current, in: interior)
            try require(error < 0.003, "Desk \(finish)/\(accent) changes the central paper (mean RGB error \(error))")
            try require(difference(normal, current, in: embossing) < 0.003,
                        "Desk \(finish)/\(accent) changes the embossing artwork")
            try capture(host, model: model, name: "desk-\(finish.rawValue)-\(accent.rawValue)", size: size)
        }
        model.preferences.deskFinish = .charcoal
        model.preferences.deskAccent = .none
        model.focusMode = true
        settle(host)
        let focused = try bitmap(host, size: size)
        for (finish, accent) in choices {
            model.preferences.deskFinish = finish
            model.preferences.deskAccent = accent
            settle(host)
            let current = try bitmap(host, size: size)
            let left = difference(focused, current, in: CGRect(x: 4, y: 50, width: 72, height: 700))
            let right = difference(focused, current, in: CGRect(x: 1004, y: 50, width: 72, height: 700))
            try require(max(left, right) < 0.003, "Focus exposes desk finish or accent \(finish)/\(accent)")
        }
        try capture(host, model: model, name: "desk-decorations-hidden-in-focus", size: size)
        print("PASS desk choices preserve the central paper and embossing, and hide from both Focus gutters")
    }

    static func renderPairedLamps() throws {
        try checkDeskSceneGeometry()
        try checkDeskLampResources()
        for size in [CGSize(width: 1080, height: 820), CGSize(width: 1733, height: 908), CGSize(width: 660, height: 580)] {
            for night in [false, true] {
                var preferences = WritingPreferences()
                preferences.paperMotion = .roll
                preferences.paperStartPosition = .bottom
                preferences.paperTexture = .cotton
                preferences.paperEmbossing = .botanical
                preferences.embossingDepth = 0.85
                preferences.nightMode = night
                preferences.soundEnabled = false
                let text = "A quiet edge of light.\nPaper, brass and native words."
                let model = AppModel(preferences: preferences, text: text)
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isRestorable = false
                window.isReleasedWhenClosed = false
                defer { window.close() }
                let host = NSHostingView(rootView: WritingDesk().environmentObject(model).preferredColorScheme(.dark))
                host.sizingOptions = []
                host.frame = CGRect(origin: .zero, size: size)
                window.contentView = host
                settle(host)
                guard let editor = descendant(InkTextView.self, in: host) else {
                    throw CheckFailure(description: "Paired-lamp native editor missing")
                }
                let selection = NSRange(location: (text as NSString).length - 6, length: 5)
                editor.setSelectedRange(selection)
                settle(host)
                func checkNativeInput(_ event: String) throws {
                    try require(descendant(InkTextView.self, in: host) === editor
                                && editor.string == text && model.selectedPage?.text == text
                                && editor.selectedRange() == selection,
                                "\(event): lighting rebuilt the editor or changed native text/selection")
                }
                let paperWidth = DeskLayout.paperWidth(windowWidth: size.width, focusMode: false, widerFocusPaper: true)
                let gutter = (size.width - paperWidth) / 2
                let paper = CGRect(x: gutter + 90, y: 128, width: paperWidth - 180, height: size.height - 270)
                let left = CGRect(x: 12, y: 70, width: max(1, gutter - 46), height: size.height - 100)
                let right = CGRect(x: size.width - gutter + 34, y: 70, width: left.width, height: left.height)
                for (finish, accent) in [(DeskFinish.leather, DeskAccent.brassLamps), (.oak, .linenLamps)] {
                    let scene = DeskSceneLayout(windowWidth: size.width, windowHeight: size.height,
                                                paperWidth: paperWidth, accent: accent)
                    // Wide enough to sample the complete grazing streak, while
                    // staying on the paper and away from the outer cast shadow.
                    let edgeY = scene.edgeLightCenterY - 58 * scene.lampScale
                    let edgeHeight = 116 * scene.lampScale
                    let leftEdge = CGRect(x: gutter + 3, y: edgeY, width: 18, height: edgeHeight)
                    let rightEdge = CGRect(x: size.width - gutter - 21, y: edgeY, width: 18, height: edgeHeight)
                    let leftInset = CGRect(x: gutter + 45, y: edgeY, width: 18, height: edgeHeight)
                    let rightInset = CGRect(x: size.width - gutter - 63, y: edgeY, width: 18, height: edgeHeight)
                    model.preferences.deskFinish = finish
                    model.preferences.deskAccent = .none
                    model.focusMode = false
                    settle(host)
                    let bare = try bitmap(host, size: size)
                    model.preferences.deskAccent = accent
                    settle(host)
                    let decorated = try bitmap(host, size: size)
                    if size.width == 1733 && !night && accent == .brassLamps {
                        try capture(host, model: model, name: "desk-leather-reference-wide", size: size)
                    }
                    try checkNativeInput("\(accent): changing desk objects")
                    try require(difference(bare, decorated, in: paper) < 0.003,
                                "\(accent): paired lamps changed central paper, text or capsule pixels")
                    let leftError = difference(bare, decorated, in: left)
                    let rightError = difference(bare, decorated, in: right)
                    if size.width >= 1080 {
                        try require(leftError > 0.002 && rightError > 0.002,
                                    "\(accent): a lamp is missing from a normal gutter (\(leftError), \(rightError))")
                        try require(min(leftError, rightError) / max(leftError, rightError) > 0.25,
                                    "\(accent): paired lamps have severely unequal visibility")
                        for (side, edge, inset) in [("left", leftEdge, leftInset), ("right", rightEdge, rightInset)] {
                            let grazing = difference(bare, decorated, in: edge)
                            let inboard = difference(bare, decorated, in: inset)
                            let bareLuminance = lampColour(bare, in: edge).luminance
                            let litLuminance = lampColour(decorated, in: edge).luminance
                            try require(grazing > 0.002,
                                        "\(accent)/\(side): no visible light reaches the paper edge (\(grazing))")
                            if litLuminance <= bareLuminance {
                                try bare.representation(using: .png, properties: [:])?.write(
                                    to: output.appendingPathComponent("failed-edge-bare.png"))
                                try decorated.representation(using: .png, properties: [:])?.write(
                                    to: output.appendingPathComponent("failed-edge-lit.png"))
                            }
                            try require(litLuminance > bareLuminance,
                                        "\(accent)/\(side): desk light darkens the paper edge (\(bareLuminance) → \(litLuminance), region \(edge))")
                            try require(inboard < 0.003 && grazing > inboard * 2,
                                        "\(accent)/\(side): grazing light spills into the 46pt native text inset")
                        }
                    } else {
                        try require(difference(bare, decorated, in: CGRect(origin: .zero, size: size)) < 0.003,
                                    "\(accent): a narrow window shows a partial lamp or glow")
                    }
                    settle(host, duration: 0.05)
                    let repeated = try bitmap(host, size: size)
                    try require(max(difference(decorated, repeated, in: left),
                                    difference(decorated, repeated, in: right)) < 0.003,
                                "\(accent): desk lighting changes between idle redraws")
                    try require(max(difference(decorated, repeated, in: leftEdge),
                                    difference(decorated, repeated, in: rightEdge)) < 0.003,
                                "\(accent): grazing light changes between idle redraws")
                    if size.width >= 1080 && !night {
                        model.preferences.lampWarmth = 0
                        settle(host)
                        let cool = try bitmap(host, size: size)
                        model.preferences.lampWarmth = 1
                        settle(host)
                        let warm = try bitmap(host, size: size)
                        try checkNativeInput("\(accent): changing lamp warmth")
                        for (side, region) in [("left desk", left), ("right desk", right),
                                               ("left paper edge", leftEdge), ("right paper edge", rightEdge)] {
                            try require(difference(cool, warm, in: region) > 0.0005
                                        && lampColour(warm, in: region).warmth > lampColour(cool, in: region).warmth,
                                        "\(accent)/\(side): desk light does not respond to shared warmth")
                        }
                        try require(difference(cool, warm, in: paper) < 0.003,
                                    "\(accent): lamp warmth affects the central day-mode writing field")
                        model.preferences.lampWarmth = preferences.lampWarmth
                        model.preferences.lampIntensity = 0.25
                        settle(host)
                        let dim = try bitmap(host, size: size)
                        model.preferences.lampIntensity = 1
                        settle(host)
                        let bright = try bitmap(host, size: size)
                        try checkNativeInput("\(accent): changing lamp intensity")
                        for (side, region) in [("left desk", left), ("right desk", right),
                                               ("left paper edge", leftEdge), ("right paper edge", rightEdge)] {
                            try require(difference(dim, bright, in: region) > 0.0005
                                        && lampColour(bright, in: region).luminance > lampColour(dim, in: region).luminance,
                                        "\(accent)/\(side): desk light does not respond to shared intensity")
                        }
                        try require(difference(dim, bright, in: paper) < 0.003,
                                    "\(accent): lamp intensity affects the central day-mode writing field")
                        model.preferences.lampIntensity = preferences.lampIntensity
                        settle(host)
                    }
                    let name = "desk-lamps-\(Int(size.width))-\(accent.rawValue)-\(night ? "night" : "day")"
                    try capture(host, model: model, name: name, size: size)
                    model.focusMode = true
                    settle(host)
                    try checkNativeInput("\(accent): entering Focus")
                    let focusedLamps = try bitmap(host, size: size)
                    model.preferences.deskAccent = .none
                    settle(host)
                    let focusedBare = try bitmap(host, size: size)
                    try require(difference(focusedBare, focusedLamps, in: CGRect(origin: .zero, size: size)) < 0.003,
                                "\(accent): Focus Mode retained a lamp or decorative light")
                    model.preferences.deskAccent = accent
                    settle(host)
                    try capture(host, model: model, name: name + "-focus", size: size)
                    print("PASS \(name): paired visibility errors \(leftError), \(rightError), native writing preserved and Focus clear")
                }
            }
        }
    }

    static func checkDeskSceneGeometry() throws {
        for (width, height, visible) in [(1080.0, 820.0, true), (1733.0, 908.0, true), (660.0, 580.0, false)] {
            let paper = DeskLayout.paperWidth(windowWidth: width, focusMode: false, widerFocusPaper: true)
            for accent in [DeskAccent.brassLamps, .linenLamps] {
                let scene = DeskSceneLayout(windowWidth: width, windowHeight: height, paperWidth: paper, accent: accent)
                try require(scene.isVisible == visible, "Scene \(width): incorrect lamp visibility")
                try require(abs(scene.leftEmitterX + scene.rightEmitterX - width) < 0.0001,
                            "Scene \(width): sources do not share the centered paper coordinate system")
                try require(scene.emitterY < scene.footY && scene.edgeLightCenterY > scene.emitterY,
                            "Scene \(width): light should originate above the foot and fall below the shade")
                if visible {
                    try require(scene.leftLampX >= 12 && scene.leftEmitterX < scene.gutter
                                && scene.rightEmitterX > width - scene.gutter,
                                "Scene \(width): lamp housing or source crosses the paper")
                    let edge = scene.paperLight(distance: 0, sceneY: scene.edgeLightCenterY)
                    let fade = scene.paperLight(distance: 20, sceneY: scene.edgeLightCenterY)
                    try require(edge > 0.1 && fade > 0 && fade < edge * 0.5,
                                "Scene \(width): edge field has no convincing inboard falloff")
                    try require(scene.paperLight(distance: 42, sceneY: scene.edgeLightCenterY) == 0
                                && scene.paperLight(distance: 46, sceneY: scene.edgeLightCenterY) == 0,
                                "Scene \(width): paper light reaches native text inset")
                    try require(scene.paperLight(distance: 0, sceneY: scene.emitterY - 30) == 0,
                                "Scene \(width): desk lamp shines upward through its opaque shade")
                }
                let hidden = DeskSceneLayout(windowWidth: width, windowHeight: height, paperWidth: paper,
                                             accent: accent, enabled: false)
                try require(!hidden.isVisible && hidden.paperLight(distance: 0, sceneY: scene.edgeLightCenterY) == 0,
                            "Scene \(width): disabled scene retains paper light")
            }
        }
        try require(DeskSceneLayout.desktopLight(x: 30, y: 100) > DeskSceneLayout.desktopLight(x: 280, y: 100),
                    "Projected desk light is not concentrated under the source")
        try require(DeskSceneLayout.desktopLight(x: 30, y: -30) == 0
                    && DeskSceneLayout.desktopLight(x: 30, y: 400) == 0,
                    "Projected desk light has no bounded source/falloff")
        print("PASS shared desk/paper source geometry and 42pt grazing-light bounds")
    }

    static func checkDeskLampResources() throws {
        for name in ["desk-lamp-brass-body", "desk-lamp-brass-emitter", "desk-lamp-linen-body", "desk-lamp-linen-emitter"] {
            guard let url = InkrailResources.bundle.url(forResource: name, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let bitmap = NSBitmapImageRep(data: data) else {
                throw CheckFailure(description: "Native desk lamp resource missing or unreadable: \(name)")
            }
            try require(bitmap.pixelsWide >= 320 && bitmap.pixelsHigh >= 540 && bitmap.hasAlpha,
                        "\(name): original lamp asset lacks transparent Retina-sized pixels")
            var covered = 0, transparent = 0
            let minimumAlpha = name.hasSuffix("-emitter") ? 0.05 : 0.8
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
                    guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                    if colour.alphaComponent > minimumAlpha { covered += 1 }
                    if colour.alphaComponent < 0.01 { transparent += 1 }
                }
            }
            try require(covered > 5 && transparent > 100,
                        "\(name): asset is blank or contains an opaque backdrop instead of a separate lamp layer")
            if name.hasSuffix("-emitter") {
                let accent: DeskAccent = name.contains("linen") ? .linenLamps : .brassLamps
                let scene = DeskSceneLayout(windowWidth: 1080, windowHeight: 820, paperWidth: 720, accent: accent)
                let localX = (scene.leftEmitterX - scene.leftLampX) / scene.lampScale
                let localY = (scene.emitterY - scene.lampTop) / scene.lampScale
                let scaleX = Double(bitmap.pixelsWide) / DeskSceneLayout.lampWidth
                let scaleY = Double(bitmap.pixelsHigh) / DeskSceneLayout.lampHeight
                var sourceAlpha = 0.0
                for y in Int((localY - 3) * scaleY)...Int((localY + 3) * scaleY) {
                    for x in Int((localX - 3) * scaleX)...Int((localX + 3) * scaleX) {
                        sourceAlpha = max(sourceAlpha, bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                    }
                }
                try require(sourceAlpha > 0.05,
                            "\(name): shared light-source coordinates miss the rendered emission mask")
            }
        }
        print("PASS original lamp body/emitter PNG resources are readable and independently transparent")
    }

    static func renderPaperBlendDiagnostic() throws {
        let size = CGSize(width: 720, height: 708)
        var p = WritingPreferences()
        p.paperTexture = .cotton
        p.paperMotion = .roll
        p.paperStartPosition = .bottom
        let scene = DeskSceneLayout(windowWidth: 1080, windowHeight: 820, paperWidth: 720)
        let bare = PaperSurface(preferences: p).frame(width: size.width, height: size.height)
        let defaultCanvas = Canvas { context, _ in
            if let paper = context.resolveSymbol(id: 0) { context.draw(paper, at: .zero, anchor: .topLeading) }
        } symbols: { bare.tag(0) }
        let linearCanvas = Canvas(colorMode: .linear) { context, _ in
            if let paper = context.resolveSymbol(id: 0) { context.draw(paper, at: .zero, anchor: .topLeading) }
        } symbols: { bare.tag(0) }
        let views: [(String, AnyView)] = [
            ("paper-direct", AnyView(bare)),
            ("paper-canvas-default", AnyView(defaultCanvas)),
            ("paper-canvas-linear", AnyView(linearCanvas)),
            ("paper-lit-current", AnyView(DeskLitPaperMaterial(scene: scene, size: size, preferences: p)))
        ]
        for (name, view) in views {
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
                .compositingGroup().preferredColorScheme(.dark))
            host.sizingOptions = []
            host.frame = CGRect(origin: .zero, size: size)
            window.contentView = host
            settle(host, duration: 0.1)
            let image = try bitmap(host, size: size)
            let edge = CGRect(x: 3, y: scene.edgeLightCenterY - 58 * scene.lampScale - scene.paperTop,
                              width: 18, height: 116 * scene.lampScale)
            let colour = lampColour(image, in: edge)
            print("DIAGNOSTIC \(name): edge luminance \(colour.luminance), warmth \(colour.warmth)")
            try image.representation(using: .png, properties: [:])?.write(
                to: output.appendingPathComponent(name + ".png"))
            window.close()
        }
        print("Paper-only Canvas controls and current light rendered; this diagnostic is not a pass/fail regression.")
    }

    static func renderEmbossingInvariant() throws {
        for motion in [PaperMotion.sheet, .roll] {
            for mark in PaperEmbossing.allCases where mark != .none {
                var extents: [CGRect] = []
                for width in [720.0, 960.0] {
                    var p = WritingPreferences()
                    p.paperMotion = motion
                    p.paperEmbossing = mark
                    p.embossingDepth = 0.9
                    let renderer = ImageRenderer(content: PaperSurface(preferences: p)
                        .frame(width: width, height: 708))
                    renderer.scale = 1
                    guard let markedImage = renderer.cgImage else { throw CheckFailure(description: "Cannot render embossing") }
                    p.paperEmbossing = .none
                    let blankRenderer = ImageRenderer(content: PaperSurface(preferences: p)
                        .frame(width: width, height: 708))
                    blankRenderer.scale = 1
                    guard let blankImage = blankRenderer.cgImage else { throw CheckFailure(description: "Cannot render blank paper") }
                    let marked = NSBitmapImageRep(cgImage: markedImage)
                    let blank = NSBitmapImageRep(cgImage: blankImage)
                    var minX = Int(width), minY = 708, maxX = -1, maxY = -1
                    var changed = 0
                    for y in 8..<165 {
                        for x in (Int(width) - 180)..<(Int(width) - 8) {
                            guard let a = marked.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                                  let b = blank.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                            let error = max(abs(a.redComponent - b.redComponent),
                                max(abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent)))
                            if error > 0.012 {
                                minX = min(minX, x); maxX = max(maxX, x)
                                minY = min(minY, y); maxY = max(maxY, y)
                                changed += 1
                            }
                        }
                    }
                    try require(changed > 50, "\(motion)/\(mark): relief disappeared at \(width) points")
                    let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                    try require(bounds.width <= 100 && bounds.height <= 100,
                                "\(motion)/\(mark): relief exceeded its 96pt artwork frame at \(width)")
                    extents.append(bounds)
                    try marked.representation(using: .png, properties: [:])!
                        .write(to: output.appendingPathComponent("focus-emboss-\(motion.rawValue)-\(mark.rawValue)-\(Int(width)).png"))
                }
                try require(abs(extents[0].width - extents[1].width) <= 2
                            && abs(extents[0].height - extents[1].height) <= 2,
                            "\(motion)/\(mark): Focus stretched the relief: \(extents)")
                try require(abs(extents[0].midY - extents[1].midY) <= 1,
                            "\(motion)/\(mark): Focus moved the relief vertically")
                print("PASS \(motion.rawValue)/\(mark.rawValue) emboss pixels retain size and height: \(extents[0].size) → \(extents[1].size)")
            }
        }
    }
    static func settle(_ host: NSView, duration: Double = 0.65) {
        let deadline = Date(timeIntervalSinceNow: duration)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
        host.layoutSubtreeIfNeeded()
    }
    static func capsuleFocusView(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).contains("FocusRingView"), view.bounds.size == CGSize(width: 116, height: 100) { return view }
        for child in view.subviews { if let match = capsuleFocusView(in: child) { return match } }
        return nil
    }
    static func meanLuminance(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> Double {
        var total = 0.0
        for dy in -2...2 { for dx in -2...2 {
            if let color = bitmap.colorAt(x: x + dx, y: y + dy)?.usingColorSpace(.deviceRGB) {
                total += 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
            }
        }}
        return total / 25
    }
    /// Three opaque housing patches, away from the central badges. The same
    /// production CapsuleView supplies a centered reference for every material,
    /// so dark styles are checked without assuming a light-colored housing.
    static func expectedHousing(_ preferences: WritingPreferences) throws -> [Double] {
        let key = "\(preferences.mechanismStyle.rawValue)-\(preferences.nightMode)"
        if let cached = referencePatches[key] { return cached }
        let size = CGSize(width: 300, height: 200)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView:
            CapsuleView(finish: preferences.capsule, style: preferences.mechanismStyle,
                        lampOn: preferences.nightMode, lampWarmth: preferences.lampWarmth,
                        lampIntensity: preferences.lampIntensity)
                .frame(width: size.width, height: size.height)
                .background(DeskPalette.paper).preferredColorScheme(.dark))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        settle(host, duration: 0.05)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 200,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let values = patchOffsets.map { meanLuminance(bitmap, x: 150 + Int($0.x), y: 100 + Int($0.y)) }
        referencePatches[key] = values
        return values
    }
    static func renderMatrix(_ preferences: WritingPreferences, size: CGSize) throws {
        let text = String(repeating: "a", count: 50)
        let model = AppModel(preferences: preferences, text: text)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: WritingDesk().environmentObject(model).preferredColorScheme(.dark))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        settle(host)
        guard let editor = descendant(InkTextView.self, in: host) else {
            throw CheckFailure(description: "matrix: native editor missing")
        }
        func captureEdges(_ name: String) throws {
            for (edge, location) in [("left", 0), ("right", 50)] {
                editor.setSelectedRange(NSRange(location: location, length: 0))
                settle(host)
                try capture(host, model: model, name: "\(name)-\(edge)", size: size)
            }
        }
        for motion in [PaperMotion.sheet, .roll] {
            for start in [PaperStartPosition.top, .bottom] {
                model.preferences.paperMotion = motion
                model.preferences.paperStartPosition = start
                try captureEdges("mode-\(motion.rawValue)-\(start.rawValue)")
            }
        }
        for style in MechanismStyle.allCases {
            model.preferences.mechanismStyle = style
            for night in [false, true] {
                model.preferences.nightMode = night
                try captureEdges("style-\(style.rawValue)-\(night ? "night" : "day")")
            }
        }
    }
    static func viewTree(_ view: NSView) -> [String: Any] {
        ["class": String(describing: type(of: view)), "frame": NSStringFromRect(view.frame),
         "bounds": NSStringFromRect(view.bounds), "hidden": view.isHidden,
         "wantsLayer": view.wantsLayer, "layerFrame": view.layer.map { NSStringFromRect($0.frame) } ?? "none",
         "layerZPosition": view.layer?.zPosition ?? 0,
         "children": view.subviews.map(viewTree)]
    }
    static func render(_ preferences: WritingPreferences, size: CGSize, text: String,
                       name: String, defaultSizing: Bool, transitions: Bool = false) throws {
        let model = AppModel(preferences: preferences, text: text)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: WritingDesk().environmentObject(model).preferredColorScheme(.dark))
        if !defaultSizing { host.sizingOptions = [] }
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        settle(host)
        try capture(host, model: model, name: name, size: size)
        if text.isEmpty {
            settle(host)
            try capture(host, model: model, name: name + "-repeat", size: size)
            model.edit(model.selectedPage!.id, text: "A")
            settle(host)
            try capture(host, model: model, name: name + "-typed", size: size)
            model.edit(model.selectedPage!.id, text: "")
            settle(host)
            try capture(host, model: model, name: name + "-cleared", size: size)
        }
        if name == "saved-short-default-sizing", let editor = descendant(InkTextView.self, in: host) {
            for location in [0, 1, 8, (text as NSString).length] {
                editor.setSelectedRange(NSRange(location: location, length: 0))
                settle(host)
                try capture(host, model: model, name: "selection-\(location)", size: size)
            }
        }
        if transitions {
            model.preferences.paperMotion = .sheet; settle(host)
            try capture(host, model: model, name: "transition-sheet-bottom", size: size)
            model.preferences.paperStartPosition = .top; settle(host)
            try capture(host, model: model, name: "transition-sheet-top", size: size)
            model.preferences.paperMotion = .roll; settle(host)
            try capture(host, model: model, name: "transition-roll-top", size: size)
            model.preferences.paperStartPosition = .bottom; settle(host)
            try capture(host, model: model, name: "transition-roll-bottom", size: size)
            model.preferences.mechanismStyle = MechanismStyle.allCases.last!; settle(host)
            try capture(host, model: model, name: "transition-style", size: size)
        }
    }
    static func capture(_ host: NSView, model: AppModel, name: String, size: CGSize) throws {
        guard let editor = descendant(InkTextView.self, in: host), let scroll = editor.enclosingScrollView else {
            throw CheckFailure(description: "\(name): editor not mounted")
        }
        guard editor.string == model.selectedPage?.text else {
            throw CheckFailure(description: "\(name): native text differs")
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
                                           pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CheckFailure(description: "\(name): allocation")
        }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckFailure(description: "\(name): encoding")
        }
        try png.write(to: output.appendingPathComponent("\(name).png"))
        guard let capsule = capsuleFocusView(in: host) else {
            throw CheckFailure(description: "\(name): capsule Button focus view missing")
        }
        let capsuleRect = capsule.convert(capsule.bounds, to: host)
        let centerLight = meanLuminance(bitmap, x: Int(capsuleRect.midX), y: Int(capsuleRect.midY))
        let paperRect = scroll.convert(scroll.bounds, to: host)
        let railX = capsuleRect.midX < paperRect.midX ? paperRect.maxX - 80 : paperRect.minX + 80
        let railLight = meanLuminance(bitmap, x: Int(railX), y: Int(capsuleRect.midY))
        let validatesClassic = model.preferences.mechanismStyle == .classic
            && model.preferences.capsule == .porcelain && !model.preferences.nightMode
        let expected = try expectedHousing(model.preferences)
        let actual = patchOffsets.map { meanLuminance(bitmap, x: Int(capsuleRect.midX + $0.x),
                                                      y: Int(capsuleRect.midY + $0.y)) }
        let patchError = zip(expected, actual).map { abs($0 - $1) }.max() ?? 1
        let housingVisible = (!validatesClassic || centerLight > 0.65) && patchError < 0.06
        let railVisible = !validatesClassic || railLight < 0.65
        if !housingVisible { failures.append("\(name): capsule housing absent/mismatched at \(NSStringFromRect(capsuleRect)) (luminance \(centerLight))") }
        if !railVisible { failures.append("\(name): rail absent (luminance \(railLight))") }
        let metadata: [String: Any] = [
            "housingPatchCheck": housingVisible ? "pass" : "fail",
            "housingPatchMaxError": patchError,
            "expectedHousingPatches": expected,
            "actualHousingPatches": actual,
            "mechanismStyle": model.preferences.mechanismStyle.rawValue,
            "nightMode": model.preferences.nightMode,
            "nativeSelection": NSStringFromRange(editor.selectedRange()),
            "classicHousingPixelCheck": validatesClassic ? (housingVisible ? "pass" : "fail") : "not applicable",
            "railPixelCheck": validatesClassic ? (railVisible ? "pass" : "fail") : "not applicable",
            "railLuminance": railLight,
            "capsuleButtonFrameInHost": NSStringFromRect(capsuleRect),
            "capsuleCenterLuminance": centerLight,
            "kind": "production WritingDesk isolated render; not running-app screenshot",
            "width": size.width, "height": size.height,
            "paperMotion": model.preferences.paperMotion.rawValue,
            "paperStartPosition": model.preferences.paperStartPosition.rawValue,
            "nativeTextUTF16Length": (editor.string as NSString).length,
            "nativeScrollOffset": scroll.contentView.bounds.minY,
            "nativeViewportHeight": scroll.contentView.bounds.height,
            "nativeScrollFrameInHost": NSStringFromRect(scroll.convert(scroll.bounds, to: host)),
            "viewTree": viewTree(host)
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("\(name).json"))
        print("\(housingVisible && railVisible ? "PASS" : "FAIL") \(name): native editor matches, \(Int(size.width))x\(Int(size.height)) PNG saved; capsule center luminance \(centerLight)")
        fflush(stdout)
    }
}
