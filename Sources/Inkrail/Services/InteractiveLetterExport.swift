import CommonCrypto
import CryptoKit
import Foundation
import InkrailCore
import Security

enum InteractiveLetterExport {
    private static func resource(_ name: String, _ ext: String) throws -> URL {
        guard let url = InkrailResources.bundle.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: name + "." + ext])
        }
        return url
    }

    static func html(for page: Page, preferences: WritingPreferences, seal: LetterSeal,
                     password: String? = nil) throws -> String {
        let template = try String(contentsOf: resource("InteractiveLetter", "html"), encoding: .utf8) as NSString
        let appearance: [String: Any] = [
            "seal": ["text": seal.text, "shape": seal.shape.rawValue, "color": seal.color.rawValue],
            "paper": preferences.paper.rawValue, "ribbon": preferences.ribbon.rawValue,
            "writingFont": preferences.writingFont.rawValue, "fontSize": preferences.fontSize,
            "wideMargins": preferences.wideMargins, "paperTexture": preferences.paperTexture.rawValue,
            "textureStrength": preferences.textureStrength, "paperEmbossing": preferences.paperEmbossing.rawValue,
            "embossingDepth": preferences.embossingDepth, "marginStyle": preferences.marginStyle.rawValue,
            "inkStrength": preferences.inkStrength
        ]
        let json = try JSONSerialization.data(withJSONObject: appearance, options: [.sortedKeys])
        // A JSON script is a raw-text element: escaping '<' keeps a seal inscription inside it.
        let settings = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
        let replacements = [
            "__INKRAIL_PAYLOAD__": settings,
            "__INKRAIL_INSCRIPTION__": escaped(seal.text),
            "__INKRAIL_BODY__": body(for: page),
            "__INKRAIL_WAX__": try Data(contentsOf: resource("letter-seal-wax", "png")).base64EncodedString(),
            "__INKRAIL_GRAIN__": try Data(contentsOf: resource("paper-grain", "png")).base64EncodedString(),
            "__INKRAIL_RUSTLE__": try Data(contentsOf: resource("paper-unfold", "mp3")).base64EncodedString()
        ]
        // Match only the original template. A writer can literally type any of the tokens.
        let tokens = try NSRegularExpression(pattern: "__INKRAIL_(?:PAYLOAD|INSCRIPTION|BODY|WAX|GRAIN|RUSTLE)__")
        var result = "", offset = 0, found = Set<String>()
        for token in tokens.matches(in: template as String, range: NSRange(location: 0, length: template.length)) {
            let key = template.substring(with: token.range)
            result += template.substring(with: NSRange(location: offset, length: token.range.location - offset))
            result += replacements[key]!
            found.insert(key)
            offset = NSMaxRange(token.range)
        }
        guard found.count == replacements.count else { throw CocoaError(.fileReadCorruptFile) }
        result += template.substring(from: offset)
        if let password { return try protectedHTML(result, password: password) }
        return result
    }

    private static func protectedHTML(_ letter: String, password: String) throws -> String {
        guard !password.isEmpty else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "Enter a password to protect this letter."
            ])
        }
        let wrapper = try String(contentsOf: resource("ProtectedInteractiveLetter", "html"), encoding: .utf8)
        let slot = "__INKRAIL_ENCRYPTED__"
        guard let range = wrapper.range(of: slot), wrapper.range(of: slot, options: .backwards) == range else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var salt = [UInt8](repeating: 0, count: 16)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        guard randomStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(randomStatus)) }
        var key = Data(count: 32)
        defer { key.resetBytes(in: 0..<key.count) }
        let status = password.withCString { bytes in
            key.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), bytes, password.utf8.count,
                                     salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                     600_000, output.bindMemory(to: UInt8.self).baseAddress, output.count)
            }
        }
        guard status == kCCSuccess else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "The letter could not be encrypted."])
        }
        // CryptoKit generates a fresh 96-bit nonce. Web Crypto expects the tag after the ciphertext.
        let box = try AES.GCM.seal(Data(letter.utf8), using: SymmetricKey(data: key))
        let package: [String: Any] = [
            "version": 1, "salt": Data(salt).base64EncodedString(), "iv": Data(box.nonce).base64EncodedString(),
            "ciphertext": (box.ciphertext + box.tag).base64EncodedString()
        ]
        let json = try JSONSerialization.data(withJSONObject: package, options: [.withoutEscapingSlashes])
        return wrapper.replacingCharacters(in: range, with: String(decoding: json, as: UTF8.self))
    }

    static func body(for page: Page) -> String {
        let source = page.text as NSString
        let runs = page.formatting
        var runIndex = 0, start = 0
        var output = "", fence: MarkdownFence?
        // Keep UTF-16 offsets from the editor, including when a styled run crosses lines.
        func inline(_ visible: NSRange) -> String {
            var result = "", offset = visible.location
            let end = NSMaxRange(visible)
            while runIndex < runs.count {
                let run = runs[runIndex]
                guard run.location < end else { break }
                let span = NSRange(location: run.location, length: run.length)
                let intersection = NSIntersectionRange(visible, span)
                if intersection.length > 0 {
                    result += escaped(source.substring(with: NSRange(location: offset, length: intersection.location - offset)))
                    var styled = escaped(source.substring(with: intersection))
                    for (mark, tag) in inlineTags.reversed() where run.emphasis.contains(mark) {
                        styled = "<\(tag)>" + styled + "</\(tag)>"
                    }
                    result += styled
                    offset = NSMaxRange(intersection)
                }
                guard NSMaxRange(span) <= end else { break }
                runIndex += 1
            }
            return result + escaped(source.substring(with: NSRange(location: offset, length: end - offset)))
        }
        while start < source.length {
            var end = 0, contentEnd = 0
            source.getLineStart(nil, end: &end, contentsEnd: &contentEnd, for: NSRange(location: start, length: 0))
            let line = NSRange(location: start, length: contentEnd - start)
            let boundary = MarkdownFence.delimiter(in: source, paragraph: line, closing: fence)
            let indented = source.range(of: "    ", options: .anchored, range: line).location != NSNotFound
                || source.range(of: "\t", options: .anchored, range: line).location != NSNotFound
            var tag = "p", attributes = "", visible = line
            if fence != nil || boundary != nil || indented {
                attributes = " class=\"literal-line\""
            } else if let prefix = MarkdownBlockPrefix.read(in: source, paragraph: line) {
                let after = NSMaxRange(prefix.range)
                let content = NSRange(location: after, length: contentEnd - after)
                if source.rangeOfCharacter(from: .whitespacesAndNewlines.inverted, options: [], range: content).location != NSNotFound {
                    switch prefix.kind {
                    case .heading(let level): tag = "h\(level)"; visible = content
                    case .quote: tag = "blockquote"
                    case .list: attributes = " class=\"list-line\""
                    }
                }
            }
            output += "<\(tag)\(attributes) dir=\"auto\">"
            output += visible.length == 0 ? "<br>" : inline(visible)
            output += "</\(tag)>\n"
            if let boundary { fence = fence == nil ? boundary : nil }
            start = end
            if start == source.length && end != contentEnd { output += "<p dir=\"auto\"><br></p>\n" }
        }
        return output
    }

    private static let inlineTags: [(TextEmphasis, String)] = [
        (.bold, "strong"), (.italic, "em"), (.underline, "u"), (.strikethrough, "del"), (.code, "code")
    ]

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
