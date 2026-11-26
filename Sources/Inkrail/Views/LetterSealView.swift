import SwiftUI
import InkrailCore

private extension SealColor {
    var wax: Color {
        switch self {
        case .oxblood: return Color(hex: 0x923E36)
        case .forest: return Color(hex: 0x466653)
        case .navy: return Color(hex: 0x3F526E)
        case .plum: return Color(hex: 0x734964)
        }
    }
}

struct LetterSealMark: View {
    let text: String
    let shape: SealShape
    let color: SealColor

    // Both desks use the same lit wax impressions. Crop the artwork once so
    // scrolling the letter or typing in the preview only lays out the text.
    private static let impressions: [SealShape: [SealColor: CGImage]] = {
        guard let atlas = InkrailResources.artwork("letter-seal-wax") else { return [:] }
        let rows: [SealShape] = [.round, .oval, .scalloped]
        let columns: [SealColor] = [.oxblood, .forest, .navy, .plum]
        let width = atlas.width / columns.count
        let height = atlas.height / rows.count
        var tiles: [SealShape: [SealColor: CGImage]] = [:]
        for (row, shape) in rows.enumerated() {
            for (column, color) in columns.enumerated() {
                let rect = CGRect(x: column * width, y: row * height, width: width, height: height)
                tiles[shape, default: [:]][color] = atlas.cropping(to: rect)
            }
        }
        return tiles
    }()

    var body: some View {
        let oval = shape == .oval
        ZStack {
            if let impression = Self.impressions[shape]?[color] {
                Image(decorative: impression, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                Ellipse().fill(color.wax)
                    .frame(width: oval ? 111 : 86, height: oval ? 71 : 82)
            }
            VStack {
                diamond
                Spacer()
                diamond
            }
            .frame(height: oval ? 45 : 51)
            Text(verbatim: text)
                .font(.custom("Georgia-Bold", size: text.count <= 3 ? 24 : 15))
                .foregroundColor(Color(hex: 0xF1DABB).opacity(0.80))
                .shadow(color: .black.opacity(0.58), radius: 0.35, x: -0.35, y: -0.6)
                .shadow(color: .white.opacity(0.22), radius: 0.2, x: 0.35, y: 0.45)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.42)
                .frame(width: oval ? 77 : 61, height: 37)
        }
        .frame(width: 120, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(color.rawValue.capitalized) \(shape.rawValue) wax seal, \(text)")
    }

    private var diamond: some View {
        Rectangle().fill(Color(hex: 0xF1DABB).opacity(0.62))
            .frame(width: 2, height: 2)
            .rotationEffect(.degrees(45))
    }
}

struct LetterSealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @InkrailState private var text: String
    @InkrailState private var shape: SealShape
    @InkrailState private var color: SealColor
    @InkrailState private var requirePassword = false
    @InkrailState private var password = ""
    @InkrailState private var confirmation = ""
    let existing: LetterSeal?
    let forExport: Bool
    let apply: (LetterSeal?, String?) -> Void

    init(existing: LetterSeal?, forExport: Bool = false, apply: @escaping (LetterSeal?, String?) -> Void) {
        self.existing = existing
        self.forExport = forExport
        self.apply = apply
        let draft = existing ?? LetterSeal()
        _text = InkrailState(initialValue: draft.text)
        _shape = InkrailState(initialValue: draft.shape)
        _color = InkrailState(initialValue: draft.color)
    }

    var body: some View {
        let inscription = LetterSeal.singleLine(text)
        let valid = !inscription.isEmpty && inscription.count <= LetterSeal.maximumTextLength
        let passwordsMatch = password.utf8.elementsEqual(confirmation.utf8)
        VStack(alignment: .leading, spacing: 20) {
            Text(forExport ? "Export interactive letter" : (existing == nil ? "Seal letter" : "Edit seal"))
                .font(.custom("Courier", size: 23))
            HStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xE6E1CE))
                    RoundedRectangle(cornerRadius: 6).strokeBorder(DeskPalette.ink.opacity(0.12))
                    LetterSealMark(text: String(inscription.prefix(LetterSeal.maximumTextLength)), shape: shape, color: color)
                }
                .frame(width: 150)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Inscription")
                            Spacer()
                            Text("\(inscription.count)/\(LetterSeal.maximumTextLength)")
                                .foregroundColor(inscription.count > LetterSeal.maximumTextLength ? .red : .secondary)
                                .monospacedDigit()
                                .accessibilityLabel("\(inscription.count) of \(LetterSeal.maximumTextLength) characters")
                        }
                        TextField("Your text", text: $text)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Seal inscription")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Shape")
                        Picker("Shape", selection: $shape) {
                            ForEach(SealShape.allCases, id: \.self) { shape in
                                Text(shape.rawValue.capitalized).tag(shape)
                            }
                        }
                        .labelsHidden().pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Wax color")
                        HStack(spacing: 7) {
                            ForEach(SealColor.allCases, id: \.self) { tint in
                                Button { color = tint } label: {
                                    Circle().fill(tint.wax)
                                        .frame(width: 18, height: 18)
                                        .padding(3)
                                        .overlay(Circle().strokeBorder(color == tint ? DeskPalette.ink : .clear, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .help(tint.rawValue.capitalized)
                                .accessibilityLabel(tint.rawValue.capitalized)
                                .accessibilityAddTraits(color == tint ? .isSelected : [])
                            }
                            Text(color.rawValue.capitalized).foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: 240)
            }
            if forExport {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Require a password", isOn: $requirePassword)
                        .onChange(of: requirePassword) { enabled in
                            if !enabled { password = ""; confirmation = "" }
                        }
                    if requirePassword {
                        SecureField("Password", text: $password)
                        SecureField("Confirm password", text: $confirmation)
                        if !confirmation.isEmpty && !passwordsMatch {
                            Text("The passwords don’t match.").foregroundColor(.red)
                        }
                        Text("Share the password separately. Inkrail can’t recover it.")
                            .foregroundColor(.secondary)
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            Divider()
            HStack {
                if existing != nil && !forExport {
                    Button("Remove seal") { apply(nil, nil); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(forExport ? "Continue to export…" : (existing == nil ? "Apply seal" : "Save changes")) {
                    apply(LetterSeal(text: inscription, shape: shape, color: color),
                          requirePassword ? password : nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(DeskPrimaryButtonStyle())
                .disabled(!valid || (requirePassword && (password.isEmpty || !passwordsMatch)))
            }
        }
        .font(.system(size: 12))
        .foregroundColor(DeskPalette.ink)
        .padding(24)
        .background(DeskPalette.paper)
        .preferredColorScheme(.light)
        .onDisappear {
            password = ""
            confirmation = ""
        }
    }
}
