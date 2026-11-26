import CommonCrypto
import CryptoKit
import Foundation
import InkrailCore

extension Bundle {
    static let module = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1])
        .appendingPathComponent("FixtureResources.bundle"))!
}

@main private enum InteractiveLetterCheck {
    private struct EncryptedLetter: Decodable {
        let version: Int
        let salt: Data
        let iv: Data
        var ciphertext: Data

        static func read(from html: String) throws -> Self {
            let start = html.range(of: #"<script\b[^>]*\bid="encrypted-letter"[^>]*>"#, options: .regularExpression)!.upperBound
            let end = html.range(of: "</script>", range: start..<html.endIndex)!.lowerBound
            return try JSONDecoder().decode(Self.self, from: Data(html[start..<end].utf8))
        }

        // Independently consume the public v1 envelope, including the Web Crypto GCM tag layout.
        func open(with password: String) throws -> Data {
            precondition(version == 1 && salt.count == 16 && iv.count == 12 && ciphertext.count > 16)
            let input = password.utf8.map { CChar(bitPattern: $0) }
            var key = [UInt8](repeating: 0, count: 32)
            let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), input, input.count,
                                              Array(salt), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                              600_000, &key, key.count)
            precondition(status == kCCSuccess)
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv),
                                            ciphertext: ciphertext.dropLast(16), tag: ciphertext.suffix(16))
            return try AES.GCM.open(box, using: SymmetricKey(data: key))
        }
    }

    private static func checkAuthenticationFails(_ envelope: EncryptedLetter, password: String) throws {
        do {
            _ = try envelope.open(with: password)
            preconditionFailure("Invalid credentials or a modified letter must fail authentication.")
        } catch CryptoKitError.authenticationFailure {}
    }

    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let seal = LetterSeal(text: "</script> & ✉️", shape: .scalloped, color: .plum)
        let text = "# A heading\n\nDear Zoë,\n\n<sample> & __INKRAIL_PAYLOAD__\n\n```\n# literal\n```"
        let name = (text as NSString).range(of: "Zoë")
        var page = Page(text: text, formatting: [.init(location: name.location, length: name.length, emphasis: .bold)])
        page.setPrivateTitle("private library label 728")
        var preferences = WritingPreferences()
        preferences.paper = .cream
        preferences.marginStyle = .botanical
        let html = try InteractiveLetterExport.html(for: page, preferences: preferences, seal: seal)
        precondition(!html.contains(page.privateTitle!) && !html.contains(page.id.uuidString))
        precondition(html.contains("&lt;sample&gt;") && html.contains("__INKRAIL_PAYLOAD__"))
        precondition(html.contains("data:image/png;base64,") && html.contains("# literal"))
        precondition(!html.contains("__INKRAIL_WAX__") && !html.contains("__INKRAIL_GRAIN__"))
        precondition(html.contains("&lt;/script&gt; &amp; ✉️"), "The inscription must also be readable without JavaScript.")
        let recordingURL = Bundle.module.url(forResource: "paper-unfold", withExtension: "mp3")!
        let recording = try Data(contentsOf: recordingURL)
        let audioStart = html.range(of: #"<script\b[^>]*\bid="paper-rustle"[^>]*>"#, options: .regularExpression)!.upperBound
        let audioEnd = html.range(of: "</script>", range: audioStart..<html.endIndex)!.lowerBound
        let encoded = html[audioStart..<audioEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!recording.isEmpty && Data(base64Encoded: encoded) == recording,
                     "The exported letter must contain the complete bundled paper recording.")

        // An inscription can contain end-tag text. It must round-trip in the JSON
        // data block without ever being parsed as an HTML end tag.
        let dataStart = html.range(of: #"<script\b[^>]*\btype=["']application/json["'][^>]*>"#,
                                   options: [.regularExpression, .caseInsensitive])!.upperBound
        let dataEnd = html.range(of: "</script>", range: dataStart..<html.endIndex)!.lowerBound
        let json = try JSONSerialization.jsonObject(with: Data(html[dataStart..<dataEnd].utf8)) as! [String: Any]
        let wax = json["seal"] as! [String: String]
        precondition(wax == ["text": seal.text, "shape": "scalloped", "color": "plum"])
        precondition(json["paper"] as? String == "cream" && json["marginStyle"] as? String == "botanical")
        try html.write(to: directory.appendingPathComponent("formatting-check.html"), atomically: true, encoding: .utf8)

        let example = Page(markdown: """
        Dear Mira,

        The first rain of the season arrived this morning. I opened the kitchen window and found the little blue cup you left on the sill.

        I’m keeping it there. When you come back, I’ll put the kettle on.

        *Always,*
        A.
        """)
        let letter = try InteractiveLetterExport.html(for: example, preferences: preferences,
                                                       seal: LetterSeal(text: "A", shape: .round, color: .oxblood))
        try letter.write(to: directory.appendingPathComponent("A letter for you.html"), atomically: true, encoding: .utf8)
        let samplePassword = "little blue cup at dawn"
        let sealed = LetterSeal(text: "For Mira", shape: .round, color: .oxblood)
        let locked = try InteractiveLetterExport.html(for: example, preferences: preferences, seal: sealed, password: samplePassword)
        precondition(!locked.contains("Dear Mira") && !locked.contains("For Mira") && !locked.contains(samplePassword))
        precondition(!locked.contains("data:image/png;base64,") && !locked.contains("__INKRAIL_ENCRYPTED__"))
        let first = try EncryptedLetter.read(from: locked)
        let second = try EncryptedLetter.read(from: InteractiveLetterExport.html(for: example, preferences: preferences,
                                                                                 seal: sealed, password: samplePassword))
        precondition(first.salt != second.salt && first.iv != second.iv, "Each export requires a fresh salt and nonce.")
        let original = try InteractiveLetterExport.html(for: example, preferences: preferences, seal: sealed)
        let decrypted = try first.open(with: samplePassword)
        precondition(decrypted == Data(original.utf8), "Decryption must restore the complete standalone HTML byte for byte.")
        try checkAuthenticationFails(first, password: samplePassword + " ")
        var altered = first
        altered.ciphertext[0] ^= 1
        try checkAuthenticationFails(altered, password: samplePassword)
        try locked.write(to: directory.appendingPathComponent("A locked letter.html"), atomically: true, encoding: .utf8)
        print("Interactive letters preserve text, export styling and seal data, with private library metadata omitted.")
    }
}
