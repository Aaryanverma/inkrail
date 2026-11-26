import SwiftUI
import InkrailCore

@MainActor
struct WritingDesk: View {
    @EnvironmentObject private var model: AppModel
    @InkrailState private var headerHovered = false
    @InkrailState private var footerHovered = false
    @InkrailState private var pendingExport: (page: Page, seal: LetterSeal, password: String?)?

    var body: some View {
        GeometryReader { geometry in
            // Resize the actual paper/editor once; never scale a snapshot of
            // the sheet. Embossing keeps its point size and Roll keeps its bend.
            let paperWidth = DeskLayout.paperWidth(windowWidth: geometry.size.width,
                focusMode: model.focusMode, widerFocusPaper: model.preferences.widerFocusPaper)
            let paperHeight = max(440.0, geometry.size.height - 112)
            let scene = DeskSceneLayout(windowWidth: geometry.size.width, windowHeight: geometry.size.height,
                                        paperWidth: paperWidth, accent: model.preferences.deskAccent,
                                        enabled: !model.focusMode && (model.preferences.deskAccent == .brassLamps
                                            || model.preferences.deskAccent == .linenLamps))
            ZStack {
                DeskBackdrop(finish: model.preferences.deskFinish, accent: model.preferences.deskAccent,
                             paperWidth: paperWidth, focusMode: model.focusMode,
                             nightMode: model.preferences.nightMode,
                             lampWarmth: model.preferences.lampWarmth,
                             lampIntensity: model.preferences.lampIntensity)
                VStack(spacing: 0) {
                    header(width: paperWidth)
                        .frame(height: 58)
                        .opacity(model.focusMode && !headerHovered ? 0.12 : 1)
                        .contentShape(Rectangle())
                        .onHover { headerHovered = $0 }
                    if let page = model.selectedPage {
                        PaperStage(page: page, deskScene: scene)
                            .frame(width: paperWidth, height: paperHeight)
                            .shadow(color: .black.opacity(0.40), radius: 25, y: 14)
                    }
                    footer
                        .frame(height: 48)
                        .opacity(model.focusMode && !footerHovered ? 0.12 : 1)
                        .contentShape(Rectangle())
                        .onHover { footerHovered = $0 }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .sheet(isPresented: $model.showLibrary, onDismiss: { model.focusEditor() }) {
            LetterBox().environmentObject(model)
        }
        .sheet(isPresented: $model.showStudio, onDismiss: { model.focusEditor() }) {
            StudioView().environmentObject(model)
        }
        .sheet(item: $model.sealEditorPage, onDismiss: { model.focusEditor() }) { page in
            LetterSealSheet(existing: page.seal) { seal, _ in model.setSeal(seal, for: page.id) }
        }
        .sheet(item: $model.interactiveExportPage, onDismiss: {
            if let pendingExport {
                self.pendingExport = nil
                model.saveInteractiveLetter(pendingExport.page, seal: pendingExport.seal, password: pendingExport.password)
            } else {
                model.focusEditor()
            }
        }) { page in
            LetterSealSheet(existing: page.seal, forExport: true) { seal, password in
                if let seal { pendingExport = (page, seal, password) }
            }
        }
        .alert("Your writing", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func header(width: CGFloat) -> some View {
        HStack(spacing: 5) {
            QuietButton(symbol: "tray", label: "Letter box · ⇧⌘O", onDark: true) { model.showLibrary = true }
            QuietButton(symbol: "plus", label: "New letter · ⌘N", onDark: true) { model.createPage() }
            Spacer()
            Text("\(model.selectedPage?.characterCount ?? 0)")
                .font(.custom("Courier", size: 11))
                .tracking(1.4)
                .foregroundColor(Color(hex: 0x9C9E8E))
                .accessibilityLabel("\(model.selectedPage?.characterCount ?? 0) characters")
            Circle()
                .fill(model.isDirty ? Color(hex: 0xBCA677) : Color(hex: 0x7D8B69))
                .frame(width: 4, height: 4)
                .padding(.leading, 8)
                .help(model.saveState)
        }
        .frame(width: width - 12)
        .overlay {
            HStack(spacing: 8) {
                InkrailMakerMark(width: 22)
                    .foregroundColor(Color(hex: 0xBCAC84))
                Text("INKRAIL")
                    .font(.custom("Courier-Bold", size: 10))
                    .tracking(2.7)
                    .foregroundColor(Color(hex: 0xB4B6A5))
            }
            .allowsHitTesting(false)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(model.selectedPage?.wordCount ?? 0) words")
            Text("·")
            Text(model.saveState.lowercased())
        }
        .font(.custom("Courier", size: 10))
        .foregroundColor(Color(hex: 0x969A88).opacity(0.65))
    }
}

@MainActor
struct PaperStage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: Page
    var deskScene: DeskSceneLayout? = nil
    @InkrailState private var caret = CaretPosition()
    @InkrailState private var striking = false
    @InkrailState private var strokeSequence = 0
    @InkrailState private var controlsHovered = false
    @InkrailState private var activeEmphasis: TextEmphasis = []

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let startPosition = model.preferences.effectivePaperStartPosition
            let rolling = model.preferences.paperMotion == .roll
            let editorHeight = PaperFeedLayout.editorHeight(paperHeight: height, position: startPosition,
                                                           motion: model.preferences.paperMotion)
            let placeholderTop = caret.startPosition == startPosition ? caret.top
                : PaperFeedLayout.topInset(viewportHeight: editorHeight,
                                           lineHeight: model.preferences.fontSize * 1.2, position: startPosition)
            let headX = min(width - 64, max(64, caret.x))
            let railY = caret.railCenterY(paperHeight: height, editorHeight: editorHeight,
                                          position: startPosition, hasText: !page.text.isEmpty)
            ZStack(alignment: .topLeading) {
                LitPaperSurface(size: geometry.size, headX: headX, railY: railY,
                                preferences: model.preferences, feedOffset: caret.scrollOffset,
                                deskScene: deskScene)
                PaperEditor(
                    page: page, currentPage: { model.selectedPage },
                    preferences: model.preferences,
                    onChange: { model.edit($0, text: $1, formatting: $2) },
                    onRestoreSeal: { model.setSeal($1, for: $0) },
                    onCaret: { position in
                        if caret.startPosition != startPosition || caret.followingTextBottom != position.followingTextBottom
                            || caret.sealFrame != position.sealFrame {
                            // Move directly to clear the text, including during scrolling.
                            caret = position
                        } else {
                            // Native scrolling drives the paper; only the carriage
                            // travels horizontally. A return is a quick slide.
                            let motion: Animation? = reduceMotion ? nil : (rolling
                                ? .easeOut(duration: position.x < caret.x - 30 ? 0.065 : 0.045)
                                : .interpolatingSpring(stiffness: 650, damping: 41))
                            withAnimation(motion) { caret = position }
                        }
                    },
                    onStroke: handleStroke,
                    onEmphasisChange: { activeEmphasis = $0 },
                    onConnect: { model.editor = $0 }
                )
                .frame(width: width, height: editorHeight)
                .overlay(alignment: .topLeading) {
                    if let seal = page.seal, let frame = caret.sealFrame {
                        LetterSealMark(text: seal.text, shape: seal.shape, color: seal.color)
                            .scaleEffect(x: frame.width / CaretPosition.sealSize.width,
                                         y: frame.height / CaretPosition.sealSize.height)
                            .position(x: frame.midX, y: frame.midY)
                            .allowsHitTesting(false)
                    }
                }
                .clipped()
                if page.text.isEmpty {
                    Text("Begin anywhere.")
                        .font(model.preferences.writingFont.font(size: model.preferences.fontSize))
                        .foregroundColor(DeskPalette.mutedInk.opacity(0.43))
                        .padding(.leading, rolling ? max(0, caret.x) : model.preferences.writingMargin)
                        .padding(.top, max(0, placeholderTop + 3))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if model.preferences.nightMode {
                    NightLighting(size: geometry.size, headX: headX, railY: railY,
                                  preferences: model.preferences, feedOffset: caret.scrollOffset, deskScene: deskScene)
                }
                RailView(finish: model.preferences.effectiveRailFinish, style: model.preferences.mechanismStyle,
                         marginStopInset: model.preferences.writingMargin + 2)
                    .frame(width: width + 4)
                    .position(x: width / 2, y: railY)
                    .brightness(model.preferences.nightMode ? -0.22 : 0)
                    .allowsHitTesting(false)
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { model.preferences.nightMode.toggle() }
                    model.focusEditor()
                } label: {
                    CapsuleView(finish: model.preferences.capsule, style: model.preferences.mechanismStyle, striking: striking, lampOn: model.preferences.nightMode,
                                lampWarmth: model.preferences.lampWarmth, lampIntensity: model.preferences.lampIntensity)
                }
                .buttonStyle(.plain)
                .position(x: headX, y: railY)
                .help("Click the capsule to toggle its lamp · ⌥⌘L")
                .accessibilityLabel("Toggle capsule lamp")
            }
            .clipShape(PaperOutline(curved: model.preferences.curvedPaper,
                                    feedOffset: rolling ? 0 : caret.scrollOffset))
            .clipped()
            // Keep the icons in place, but let their labels appear below them
            // without being cut off by the paper's lower edge.
            .overlay(alignment: .bottom) {
                bottomBar
                    .padding(.horizontal, 30)
                    .padding(.bottom, 18)
                    .opacity(model.focusMode && !controlsHovered ? 0.06 : 1)
                    .contentShape(Rectangle())
                    .onHover { controlsHovered = $0 }
            }
            .animation(nil, value: caret.scrollOffset)
            .onAppear { model.paperSizeForExport = geometry.size }
            .onChange(of: geometry.size) { model.paperSizeForExport = $0 }
            .onChange(of: page.id) { _ in caret = CaretPosition(); striking = false }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            Text(page.createdAt.formatted(.dateTime.day().month(.wide).year()).uppercased())
                .font(.custom("Courier", size: 9))
                .tracking(1.1)
                .foregroundColor(model.preferences.nightMode ? Color.white.opacity(0.32) : DeskPalette.mutedInk.opacity(0.55))
            Spacer()
            HStack(spacing: 0) {
                emphasisButton(.bold, symbol: "bold", title: "Bold", shortcut: "b")
                emphasisButton(.italic, symbol: "italic", title: "Italic", shortcut: "i")
                emphasisButton(.underline, symbol: "underline", title: "Underline", shortcut: "u")
            }
            .padding(.trailing, 10)
            QuietButton(symbol: "seal", label: page.seal == nil ? "Seal letter…" : "Edit seal…",
                        onDark: model.preferences.nightMode, active: page.seal != nil, themedHoverLabel: true) {
                model.openSealEditor()
            }
            .disabled(!page.canApplySeal)
            QuietButton(symbol: model.preferences.soundEnabled ? "speaker.wave.1" : "speaker.slash",
                        label: model.preferences.soundEnabled ? "Mute sounds · ⇧⌘M" : "Turn sounds on · ⇧⌘M",
                        onDark: model.preferences.nightMode, themedHoverLabel: true) {
                model.preferences.soundEnabled.toggle(); model.focusEditor()
            }
            Menu {
                Button("Export Interactive Letter") { model.exportInteractiveLetter() }
                    .disabled(!model.canSealSelectedPage)
                Button("Export Letter as PDF…") { model.exportPDF() }
                Button("Export Markdown…") { model.export(markdown: true) }
                Button("Export Text…") { model.export() }
            } label: {
                DeskControlIcon(symbol: "arrow.up.doc", onDark: model.preferences.nightMode)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .modifier(DeskControlHover(label: "Export letter", onDark: model.preferences.nightMode))
            QuietButton(symbol: "viewfinder",
                        label: model.focusMode ? "Exit Focus Mode · ⇧⌘F" : "Enter Focus Mode · ⇧⌘F",
                        onDark: model.preferences.nightMode, active: model.focusMode, themedHoverLabel: true) {
                model.focusMode.toggle(); model.focusEditor()
            }
            .accessibilityValue(model.focusMode ? "On" : "Off")
            QuietButton(symbol: model.preferences.nightMode ? "sun.max" : "moon",
                        label: model.preferences.nightMode ? "Day writing · ⌥⌘L" : "Night writing · ⌥⌘L",
                        onDark: model.preferences.nightMode, themedHoverLabel: true) {
                model.preferences.nightMode.toggle(); model.focusEditor()
            }
            QuietButton(symbol: "slider.horizontal.3", label: "Make it yours · ⌘,",
                        onDark: model.preferences.nightMode, themedHoverLabel: true) { model.showStudio = true }
        }
    }

    private func emphasisButton(_ emphasis: TextEmphasis, symbol: String, title: String,
                                shortcut: KeyEquivalent) -> some View {
        let active = activeEmphasis.contains(emphasis)
        return QuietButton(symbol: symbol, label: "\(title) · ⌘\(shortcut.character.uppercased())",
                           onDark: model.preferences.nightMode, active: active, themedHoverLabel: true) {
            NotificationCenter.default.post(name: .inkrailToggleEmphasis, object: emphasis)
        }
        .keyboardShortcut(shortcut)
        .accessibilityLabel(title)
        .accessibilityValue(active ? "On" : "Off")
    }

    private func handleStroke(_ kind: StrokeKind) {
        if model.preferences.soundEnabled {
            SoundEngine.shared.play(kind, volume: model.preferences.soundVolume,
                                    style: model.preferences.typewriterSound)
        }
        guard kind != .navigation, kind != .bell else { return }
        strokeSequence += 1
        let sequence = strokeSequence
        striking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.065) {
            if strokeSequence == sequence { striking = false }
        }
    }
}
