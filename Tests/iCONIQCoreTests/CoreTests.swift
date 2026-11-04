import XCTest
@testable import iCONIQCore

final class CoreTests: XCTestCase {
    func tmp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("iconiq-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><path d=\"M0 0h24v24H0z\"/></svg>".utf8)

    func testAddSearchStarDelete() throws {
        let lib = try Library(root: tmp())
        let c = try lib.addCollection(name: "Test")
        let a = try lib.addIcon(data: svg, fmt: "svg", name: "Étoile jaune", tags: "forme,Ciel", collection: c.id)
        XCTAssertEqual(a.width, 24)
        XCTAssertEqual(lib.icons(IconQuery(text: "etoile")).count, 1)
        XCTAssertEqual(lib.icons(IconQuery(text: "ciel jaune")).count, 1)
        XCTAssertEqual(lib.icons(IconQuery(text: "absent")).count, 0)
        // doublon exact ignoré
        let b = try lib.addIcon(data: svg, fmt: "svg", name: "Autre", collection: c.id)
        XCTAssertEqual(b.id, a.id)
        lib.setStarred([a.id], true)
        XCTAssertEqual(lib.icons(IconQuery(scope: .starred)).count, 1)
        lib.touch([a.id])
        XCTAssertEqual(lib.icons(IconQuery(scope: .recent)).count, 1)
        lib.delete([a.id])
        XCTAssertEqual(lib.totalCount(), 0)
    }

    func testGroupScopeAndMove() throws {
        let lib = try Library(root: tmp())
        let g = try lib.addGroup(name: "G"), sub = try lib.addGroup(name: "S", parent: g.id)
        let c1 = try lib.addCollection(name: "A", group: sub.id), c2 = try lib.addCollection(name: "B")
        let i = try lib.addIcon(data: svg, fmt: "svg", name: "x", collection: c1.id)
        XCTAssertEqual(lib.icons(IconQuery(scope: .group(g.id))).count, 1)
        lib.update(i.id, collection: c2.id)
        XCTAssertEqual(lib.icons(IconQuery(scope: .collection(c2.id))).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.fileURL(lib.icon(id: i.id)!).path))
        lib.deleteGroup(g.id)
        XCTAssertEqual(lib.collections().count, 1)
    }

    func testIconJarImport() throws {
        // Mini bibliothèque IconJar synthétique
        let src = tmp().appendingPathComponent("T.ijlibrary")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("Sets/ID-1"), withIntermediateDirectories: true)
        try svg.write(to: src.appendingPathComponent("Sets/ID-1/star.svg"))
        let db = try Database(path: src.appendingPathComponent("Jars.db").path)
        try db.exec("""
        CREATE TABLE ZIJCOLLECTION (Z_PK INTEGER PRIMARY KEY, ZSORT INTEGER, ZTYPE INTEGER, ZGROUP INTEGER, ZAUTHOR VARCHAR, ZIDENTIFIER VARCHAR, ZNAME VARCHAR, ZINFORMATIVETEXT VARCHAR);
        CREATE TABLE ZIJGROUP (Z_PK INTEGER PRIMARY KEY, ZSORT INTEGER, ZGROUP INTEGER, ZNAME VARCHAR);
        CREATE TABLE ZIJITEM (Z_PK INTEGER PRIMARY KEY, ZSTARRED INTEGER, ZWIDTH INTEGER, ZHEIGHT INTEGER, ZCOLLECTION INTEGER, ZDATE REAL, ZLASTUSEDDATE REAL,
          ZINFO VARCHAR, ZINFORMATIVETEXT VARCHAR, ZNAME VARCHAR, ZNEWFILENAME VARCHAR, ZORIGINALFILENAME VARCHAR, ZTAGSSTRING VARCHAR);
        INSERT INTO ZIJGROUP VALUES (1, 1, NULL, 'Racine');
        INSERT INTO ZIJCOLLECTION VALUES (1, 1, 0, 1, '', 'ID-1', 'Formes', '');
        INSERT INTO ZIJCOLLECTION VALUES (2, 2, 3, NULL, '', 'x', 'Starred', '');
        INSERT INTO ZIJITEM VALUES (1, 1, 24, 24, 1, 815083569, NULL, '', '', 'Star', 'star.svg', '', 'a,b');
        INSERT INTO ZIJITEM VALUES (2, 0, 24, 24, 1, 815083569, NULL, '', '', 'Ghost', 'ghost.svg', '', '');
        """)
        let lib = try Library(root: tmp())
        let r = try IconJarImporter.importLibrary(at: src, into: lib)
        XCTAssertEqual(r.collections, 1); XCTAssertEqual(r.icons, 1); XCTAssertEqual(r.missing, 1)
        let icons = lib.icons(IconQuery())
        XCTAssertEqual(icons.first?.name, "Star"); XCTAssertTrue(icons.first!.starred); XCTAssertEqual(icons.first?.tags, "a,b")
        XCTAssertEqual(lib.groups().first?.name, "Racine")
        XCTAssertEqual(lib.collections().first?.group, lib.groups().first?.id)
    }

    func testFolderImport() throws {
        let d = tmp().appendingPathComponent("Pack")
        try FileManager.default.createDirectory(at: d.appendingPathComponent("a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: d.appendingPathComponent("b"), withIntermediateDirectories: true)
        try svg.write(to: d.appendingPathComponent("a/one.svg")); try svg.write(to: d.appendingPathComponent("b/two.svg"))
        let lib = try Library(root: tmp())
        let r = try FolderImporter.importFolder(at: d, into: lib, groupNamed: nil)
        XCTAssertEqual(r.collections, 2); XCTAssertEqual(r.icons, 2)
        XCTAssertEqual(lib.groups().first?.name, "Pack")
    }

    func testInboxCreatesThenUpdates() throws {
        let lib = try Library(root: tmp())
        let png1 = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        let png2 = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        try Inbox.submit(.init(name: "Mon icône", file: "x.png", origin: "/tmp/Mon.icns", kind: "app", source: "MiCONE"), data: png1, lib: lib)
        XCTAssertEqual(Inbox.process(lib).count, 1)
        let first = lib.icons(IconQuery(scope: .micone)).first!
        lib.setStarred([first.id], true)
        try Inbox.submit(.init(name: "Mon icône", file: "x.png", origin: "/tmp/Mon.icns", kind: "app", source: "MiCONE"), data: png2, lib: lib)
        XCTAssertEqual(Inbox.process(lib), [first.id])
        let all = lib.icons(IconQuery(scope: .micone))
        XCTAssertEqual(all.count, 1); XCTAssertTrue(all[0].starred)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: lib.inboxDir.path))?.count, 0)
    }

    func testInboxConcurrentPassesDoNotDuplicate() throws {
        let lib = try Library(root: tmp())
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        try Inbox.submit(.init(name: "A", file: "x.png", origin: "/tmp/A.icns", kind: "app", source: "MiCONE"), data: png, lib: lib)
        DispatchQueue.concurrentPerform(iterations: 6) { _ in Inbox.process(lib) }
        XCTAssertEqual(lib.icons(IconQuery(scope: .micone)).count, 1)
    }

    func testCaptureHelpers() async throws {
        XCTAssertEqual(WebCapture.searchURL(template: "https://x.io/?q={q}", query: "arrow & co")?.absoluteString, "https://x.io/?q=arrow%20%26%20co")
        XCTAssertNil(WebCapture.searchURL(template: "https://x.io/", query: "a"))
        XCTAssertEqual(WebCapture.normalizeURL("svgrepo.com")?.absoluteString, "https://svgrepo.com")
        XCTAssertNil(WebCapture.normalizeURL("pas une adresse"))
        let (d, f) = try WebCapture.decodeDataURL("data:image/svg+xml;utf8,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%2F%3E")
        XCTAssertEqual(f, "svg"); XCTAssertFalse(d.isEmpty)
        let c = CaptureCandidate(key: "k", kind: "svg", url: "", svg: "<svg viewBox=\"0 0 1 1\"><script>x</script></svg>", name: "n", width: 1, height: 1)
        let (data, fmt) = try await WebCapture.fetch(c, referer: "")
        XCTAssertEqual(fmt, "svg"); XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("script")); XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("xmlns"))
    }
}
