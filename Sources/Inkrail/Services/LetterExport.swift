import AppKit
import UniformTypeIdentifiers
import InkrailCore

@MainActor
enum LetterExport {
    static func saveText(_ page: Page, markdown: Bool) throws {
        let type = markdown ? (UTType(filenameExtension: "md") ?? .plainText) : .plainText
        guard let url = destination(filename: page.exportName + (markdown ? ".md" : ".txt"), type: type) else { return }
        let content = markdown ? page.markdownText : page.plainText
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func savePDF(_ page: Page, preferences: WritingPreferences, paperSize: CGSize) throws {
        guard let url = destination(filename: page.exportName + ".pdf", type: .pdf) else { return }
        let data = try LetterPDFExport.data(for: page, preferences: preferences, paperSize: paperSize)
        try data.write(to: url, options: .atomic)
    }

    static func saveInteractive(_ page: Page, preferences: WritingPreferences, seal: LetterSeal,
                                password: String?) async throws {
        guard let url = destination(filename: "A letter for you.html", type: .html) else { return }
        try await Task.detached(priority: .userInitiated) {
            let html = try InteractiveLetterExport.html(for: page, preferences: preferences, seal: seal, password: password)
            try html.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }

    private static func destination(filename: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = filename
        panel.title = "Keep a copy of your letter"
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
extension AppModel {
    var canSealSelectedPage: Bool {
        selectedPage?.canApplySeal == true && !showStudio && !showLibrary
            && sealEditorPage == nil && interactiveExportPage == nil
    }

    func exportInteractiveLetter() {
        editor?.commitComposition()
        guard canSealSelectedPage, let page = selectedPage else { return }
        interactiveExportPage = page
    }

    func saveInteractiveLetter(_ page: Page, seal: LetterSeal, password: String?) {
        let appearance = preferences
        Task {
            do { try await LetterExport.saveInteractive(page, preferences: appearance, seal: seal, password: password) }
            catch { errorMessage = error.localizedDescription }
            focusEditor()
        }
    }
}
