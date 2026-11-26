import AppKit
import SwiftUI

@main
@MainActor
struct InkrailApp: App {
    @NSApplicationDelegateAdaptor(InkrailDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Inkrail", id: "writing-desk") {
            WritingDesk()
                .environmentObject(model)
                .frame(minWidth: 660, minHeight: 580)
                .onAppear {
                    delegate.model = model
                    SoundEngine.shared.prepare(style: model.preferences.typewriterSound)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Inkrail") {
                    var options: [NSApplication.AboutPanelOptionKey: Any] = [
                        .applicationName: "Inkrail",
                        .credits: NSAttributedString(string: "Made with ❤︎ by Aaryan Verma")
                    ]
                    if let icon = InkrailAppIcon.image() { options[.applicationIcon] = icon }
                    NSApp.orderFrontStandardAboutPanel(options: options)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Letter") { model.createPage() }.keyboardShortcut("n")
                Button("Import Text or Markdown…") { model.importText() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.saveNow() }.keyboardShortcut("s")
                Button("Export Interactive Letter") { model.exportInteractiveLetter() }
                    .disabled(!model.canSealSelectedPage)
                Button("Export Letter as PDF…") { model.exportPDF() }
                    .disabled(model.selectedPage == nil || model.paperSizeForExport == nil)
                Button("Export Text…") { model.export() }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export Markdown…") { model.export(markdown: true) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Make It Yours…") { model.showStudio = true }.keyboardShortcut(",")
            }
            CommandMenu("Writing") {
                Button("Open Letter Box") { model.showLibrary = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button(model.selectedPage?.seal == nil ? "Seal Letter…" : "Edit Seal…") { model.openSealEditor() }
                    .disabled(!model.canSealSelectedPage)
                Button("Clear Inline Formatting") {
                    NSApp.sendAction(#selector(InkTextView.clearLetterFormatting(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("\\")
                .disabled(model.selectedPage == nil || model.showLibrary || model.showStudio)
                Divider()
                Toggle("Focus Mode", isOn: $model.focusMode)
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Toggle("Night Writing", isOn: $model.preferences.nightMode)
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Toggle("Mechanical Sounds", isOn: $model.preferences.soundEnabled)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Show Local Files") { model.revealStorage() }
            }
        }
    }
}

@MainActor
final class InkrailDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        InkrailAppIcon.install()
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.105, blue: 0.10, alpha: 1)
            window.isMovableByWindowBackground = false
        }
    }
    func applicationDidResignActive(_ notification: Notification) { _ = model?.flush() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !model.saveNow() else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Some writing has not been saved."
        alert.informativeText = "Cancel to export a copy, or quit and lose the unsaved changes."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
