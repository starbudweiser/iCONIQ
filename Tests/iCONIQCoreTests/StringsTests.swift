import XCTest

/// Les quatre langues ont les mêmes clés, et toute clé utilisée dans le code existe.
final class StringsTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func keys(_ lang: String) throws -> Set<String> {
        let url = root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
        let d = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "illisible : \(lang)")
        return Set(d.keys)
    }

    func testSameKeysEverywhere() throws {
        let fr = try keys("fr")
        for l in ["en", "es", "it"] { XCTAssertEqual(try keys(l), fr, "clés différentes en \(l)") }
    }

    func testUsedKeysExist() throws {
        let fr = try keys("fr")
        let dir = root.appendingPathComponent("Sources/iCONIQ")
        let regex = try NSRegularExpression(pattern: #"\bL\("([a-zA-Z0-9_.]+)""#)
        for f in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where f.pathExtension == "swift" && !["Updater.swift", "UpdaterView.swift"].contains(f.lastPathComponent) {
            let text = try String(contentsOf: f, encoding: .utf8)
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(m.range(at: 1), in: text)!])
                XCTAssertTrue(fr.contains(key), "clé absente : \(key) (\(f.lastPathComponent))")
            }
        }
    }

    func testPlaceholdersMatch() throws {
        func load(_ l: String) -> [String: String] { (NSDictionary(contentsOf: root.appendingPathComponent("Resources/\(l).lproj/Localizable.strings")) as? [String: String]) ?? [:] }
        func spec(_ s: String) -> [String] { s.components(separatedBy: "%").dropFirst().compactMap { $0.first.map(String.init) }.sorted() }
        let fr = load("fr")
        for l in ["en", "es", "it"] { for (k, v) in load(l) { XCTAssertEqual(spec(v), spec(fr[k] ?? ""), "paramètres différents : \(k) en \(l)") } }
    }
}
