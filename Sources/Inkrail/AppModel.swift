import AppKit
import Combine
import UniformTypeIdentifiers
import SwiftUI
import InkrailCore

extension Notification.Name {
    static let inkrailFocusEditor = Notification.Name("Inkrail.FocusEditor")
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var pages: [Page] = []
    @Published private(set) var selectedID: UUID? {
        didSet {
            if selectedID != oldValue {
                sealEditorPage = nil
                interactiveExportPage = nil
                if let selectedPage { editor?.display(selectedPage) }
            }
        }
    }
    weak var editor: (any LetterEditor)?
    @Published var paperSizeForExport: CGSize?
    @Published var preferences: WritingPreferences {
        didSet {
            if (oldValue.soundEnabled && !preferences.soundEnabled)
                || oldValue.typewriterSound != preferences.typewriterSound
                || (oldValue.soundVolume > 0 && preferences.soundVolume == 0) {
                SoundEngine.shared.stopAll()
            }
            if let bytes = try? JSONEncoder().encode(preferences) {
                defaults.set(bytes, forKey: "writing-preferences-v1")
            }
        }
    }
    @Published var showLibrary = false
    @Published var showStudio = false
    @Published var sealEditorPage: Page?
    @Published var interactiveExportPage: Page?
    @Published var focusMode = false
    @Published var errorMessage: String?
    @Published private(set) var saveState = "Saved on this Mac"
    @Published private(set) var storageAvailable = true
    @Published private(set) var storageMessage: String?
    @Published private(set) var rootURL: URL
    @Published private(set) var trashRevision = 0
    @Published private(set) var trashMaintenanceWarning: String?

    private let defaults: UserDefaults
    private let nowProvider: () -> Date
    private static let storageLocationKey = "letter-storage-folder-v1"
    private var repository: PageRepository?
    private var dirty = Set<UUID>()
    private var lastSaveFailure: String?
    private var saveWork: DispatchWorkItem?
    private var periodicSave: Timer?
    private var lastTrashMaintenance: Date?

    init(defaults: UserDefaults = .standard, defaultRootURL: URL? = nil,
         schedulesAutosave: Bool = true, nowProvider: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.nowProvider = nowProvider
        var prefs = defaults.data(forKey: "writing-preferences-v1")
            .flatMap { try? JSONDecoder().decode(WritingPreferences.self, from: $0) } ?? WritingPreferences()
        prefs.clamp()
        preferences = prefs
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let savedPath = defaults.string(forKey: Self.storageLocationKey)
        rootURL = savedPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? defaultRootURL ?? support.appendingPathComponent("Inkrail", isDirectory: true)
        do {
            // A disconnected or renamed custom folder must never become a new,
            // empty library or silently fall back to the default location.
            if savedPath != nil { try LibraryLocation.validateExistingLibrary(at: rootURL) }
            let repo = try PageRepository(rootURL: rootURL)
            repository = repo
            let report = try repo.load()
            pages = report.pages
            if !report.warnings.isEmpty { errorMessage = report.warnings.joined(separator: "\n\n") }
            if let saved = defaults.string(forKey: "selected-letter"),
               let id = UUID(uuidString: saved), pages.contains(where: { $0.id == id }) {
                selectedID = id
            } else {
                selectedID = pages.first?.id
            }
            if pages.isEmpty { createPage(text: Self.welcomeText) }
        } catch {
            // Never pretend that an unwritable store is a successful autosave.
            storageAvailable = false
            saveState = "Storage unavailable — export your writing"
            errorMessage = "Inkrail could not open its letters at \(rootURL.path). Reconnect the drive or put the folder back, then reopen Inkrail. You can still write and export, but autosave is unavailable.\n\n\(error.localizedDescription)"
            let page = Page()
            pages = [page]
            selectedID = page.id
        }
        performTrashMaintenance(force: true)
        if schedulesAutosave {
            periodicSave = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    _ = self.flush()
                    self.performTrashMaintenance()
                }
            }
        }
    }

    static let welcomeText = """
    A small room for your thoughts.

    No feeds. No noise.
    Just the next sentence.

    Make yourself at home.
    """

    var selectedPage: Page? { pages.first { $0.id == selectedID } }
    var currentText: String { selectedPage?.text ?? "" }
    var isDirty: Bool { !dirty.isEmpty }

    func edit(_ id: UUID, text: String, formatting: [TextFormatRun] = []) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        var page = pages[index]
        guard !page.text.utf8.elementsEqual(text.utf8) || page.formatting != formatting else { return }
        page.text = text
        page.formatting = formatting
        page.modifiedAt = Date()
        autosave(page, at: index)
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        var page = pages[index]
        page.setPrivateTitle(title)
        guard page.privateTitle != pages[index].privateTitle else { return }
        autosave(page, at: index)
    }

    func openSealEditor() {
        editor?.commitComposition()
        guard let page = selectedPage, page.canApplySeal else { return }
        sealEditorPage = page
    }

    func setSeal(_ seal: LetterSeal?, for id: UUID) {
        guard selectedID == id, let index = pages.firstIndex(where: { $0.id == id }) else { return }
        var page = pages[index]
        guard page.canApplySeal, page.seal != seal else { return }
        page.seal = seal
        page.modifiedAt = nowProvider()
        autosave(page, at: index)
    }

    private func autosave(_ page: Page, at index: Int) {
        pages[index] = page
        dirty.insert(page.id)
        saveState = storageAvailable ? "Saving…" : "Not saved — export your writing"
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in _ = self?.flush() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    @discardableResult
    func saveNow() -> Bool {
        editor?.commitComposition()
        return flush()
    }

    @discardableResult
    func flush() -> Bool {
        saveWork?.cancel()
        guard !dirty.isEmpty else { return true }
        guard let repo = repository, storageAvailable else { return false }
        var failed: String?
        for id in Array(dirty) {
            guard let page = pages.first(where: { $0.id == id }) else { dirty.remove(id); continue }
            do {
                try repo.save(page)
                dirty.remove(id)
            } catch {
                failed = "Could not save “\(page.title)”. Your text remains in memory. Export a copy before closing the app.\n\n\(error.localizedDescription)"
            }
        }
        if let failed {
            saveState = "Save failed — export your writing"
            if failed != lastSaveFailure { errorMessage = failed }
            lastSaveFailure = failed
            return false
        }
        lastSaveFailure = nil
        saveState = "Saved on this Mac"
        return true
    }

    func createPage(text: String = "") {
        createPage(Page(text: text))
    }

    private func createPage(_ page: Page) {
        saveNow()
        pages.insert(page, at: 0)
        selectedID = page.id
        rememberSelection()
        dirty.insert(page.id)
        _ = flush()
        showLibrary = false
        focusEditor()
    }

    func select(_ id: UUID) {
        guard pages.contains(where: { $0.id == id }) else { return }
        saveNow()
        selectedID = id
        rememberSelection()
        showLibrary = false
        focusEditor()
    }

    func moveToTrash(_ id: UUID) {
        guard saveNow(), let repo = repository else { return }
        do {
            try repo.moveToTrash(id, at: nowProvider())
            pages.removeAll { $0.id == id }
            dirty.remove(id)
            if selectedID == id { selectedID = pages.first?.id }
            if pages.isEmpty { createPage() }
            rememberSelection()
        } catch { errorMessage = error.localizedDescription }
    }

    func deletedPages() -> [Page] {
        performTrashMaintenance(force: true)
        do {
            let report = try repository?.load(inTrash: true)
            if let warnings = report?.warnings, !warnings.isEmpty {
                errorMessage = warnings.joined(separator: "\n\n")
            }
            return report?.pages ?? []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func restore(_ id: UUID) {
        guard let repo = repository else { return }
        guard !performTrashMaintenance(force: true).contains(id) else {
            errorMessage = "This letter's 30-day restore window has ended and it has been permanently deleted."
            return
        }
        do {
            let page = try repo.restore(id)
            if !pages.contains(where: { $0.id == page.id }) { pages.append(page) }
            pages.sort { $0.modifiedAt > $1.modifiedAt }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Uses the active library only. The app checks hourly while running, plus
    /// at launch and before displaying/restoring deleted letters.
    @discardableResult
    func performTrashMaintenance(force: Bool = false) -> [UUID] {
        guard storageAvailable, let repo = repository else { return [] }
        let now = nowProvider()
        if !force, let lastTrashMaintenance,
           now >= lastTrashMaintenance, now.timeIntervalSince(lastTrashMaintenance) < 3_600 {
            return []
        }
        lastTrashMaintenance = now
        do {
            let report = try repo.cleanupRecentlyDeleted(now: now)
            trashMaintenanceWarning = report.warnings.isEmpty ? nil : report.warnings.joined(separator: "\n\n")
            if !report.removedIDs.isEmpty { trashRevision += 1 }
            return report.removedIDs
        } catch {
            trashMaintenanceWarning = "Recently Deleted could not be checked. Inkrail will try again.\n\n\(error.localizedDescription)"
            return []
        }
    }

    func revealStorage() { NSWorkspace.shared.open(rootURL) }

    func chooseStorageLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose where to save your letters"
        panel.message = "Choose a new or empty folder. Inkrail copies all letters, recently deleted letters and backups there. Your current folder stays intact."
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = changeStorageLocation(to: url)
    }

    /// Commit the preference only after pending edits and the complete copy
    /// have succeeded. The source remains available as a safety copy.
    @discardableResult
    func changeStorageLocation(to destination: URL) -> Bool {
        storageMessage = nil
        guard storageAvailable, let current = repository else {
            storageMessage = "Reconnect your current letters folder and reopen Inkrail before changing its location. Export any unsaved writing first."
            return false
        }
        guard saveNow() else {
            storageMessage = "The location was not changed because pending writing could not be saved. Export a copy before closing Inkrail."
            return false
        }
        performTrashMaintenance(force: true)
        do {
            let next = try current.copyLibrary(to: destination)
            let previous = rootURL
            repository = next
            rootURL = next.rootURL
            defaults.set(rootURL.path, forKey: Self.storageLocationKey)
            saveState = "Saved on this Mac"
            storageMessage = "Letters now save here. Your previous copy remains at \(previous.path); it will no longer receive changes."
            return true
        } catch {
            storageMessage = "The location was not changed. Inkrail is still using \(rootURL.path).\n\n\(error.localizedDescription)"
            return false
        }
    }

    func export(markdown: Bool = false) {
        exportPage { try LetterExport.saveText($0, markdown: markdown) }
    }

    func exportPDF() {
        guard let paperSizeForExport else { return }
        exportPage { try LetterExport.savePDF($0, preferences: preferences, paperSize: paperSizeForExport) }
    }

    private func exportPage(_ save: (Page) throws -> Void) {
        editor?.commitComposition()
        guard let page = selectedPage else { return }
        do { try save(page) }
        catch { errorMessage = error.localizedDescription }
        focusEditor()
    }

    func importText() {
        let panel = NSOpenPanel()
        panel.title = "Bring a letter to your desk"
        panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { focusEditor(); return }
        do {
            try importText(from: url)
        } catch { errorMessage = error.localizedDescription }
    }

    func importText(from url: URL) throws {
        var encoding = String.Encoding.utf8
        let text = try String(contentsOf: url, usedEncoding: &encoding)
        let isMarkdown = ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased())
        createPage(isMarkdown ? Page(markdown: text) : Page(text: text))
    }

    func focusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .inkrailFocusEditor, object: nil)
        }
    }

    private func rememberSelection() {
        defaults.set(selectedID?.uuidString, forKey: "selected-letter")
    }
}
