import Foundation

public struct ImportReport: Sendable {
    public var collections = 0
    public var icons = 0
    public var missing = 0
    public var skipped = 0
}

public typealias ProgressHandler = @Sendable (Double, String) -> Void

public enum IconJarImporter {
    /// Bibliothèque IconJar (`.ijlibrary`, `.iconjarlibrary`) ou jar (`.iconjar`) : contient `Jars.db`.
    public static func isLibrary(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("Jars.db").path)
    }

    /// Importe tout : groupes, collections, icônes (SVG et bitmaps), étiquettes, favoris. Les fichiers sont copiés dans iCONIQ.
    @discardableResult
    public static func importLibrary(at url: URL, into lib: Library, progress: ProgressHandler = { _, _ in }) throws -> ImportReport {
        guard isLibrary(url) else { return try importPackage(at: url, into: lib, progress: progress) }
        let src = try Database(path: url.appendingPathComponent("Jars.db").path, readOnly: true)
        var report = ImportReport()
        let fm = FileManager.default

        // Groupes (arborescence) : Z_PK source -> id iCONIQ
        var groupID: [Int: String] = [:]
        let groupRows = try src.query("SELECT Z_PK, ZGROUP, ZNAME, ZSORT FROM ZIJGROUP ORDER BY ZSORT")
        for r in groupRows { groupID[r.int("Z_PK")] = UUID().uuidString }
        try lib.db.transaction {
            for r in groupRows {
                let parent = r.int("ZGROUP") > 0 ? groupID[r.int("ZGROUP")] : nil
                try lib.addGroup(name: r.string("ZNAME") ?? "?", parent: parent, id: groupID[r.int("Z_PK")]!, sort: r.int("ZSORT"))
            }
        }

        // Collections ordinaires (ZTYPE 0) ; les intelligentes (favoris, récents…) sont recalculées par iCONIQ.
        let collRows = try src.query("SELECT Z_PK, ZGROUP, ZSORT, ZIDENTIFIER, ZNAME, ZAUTHOR, ZINFORMATIVETEXT FROM ZIJCOLLECTION WHERE ZTYPE=0 ORDER BY ZSORT, Z_PK")
        var collID: [Int: (id: String, sourceDir: String)] = [:]
        for r in collRows {
            let id = UUID().uuidString
            collID[r.int("Z_PK")] = (id, r.string("ZIDENTIFIER") ?? "")
            let g = r.int("ZGROUP") > 0 ? groupID[r.int("ZGROUP")] : nil
            try lib.addCollection(name: r.string("ZNAME") ?? "?", group: g, author: r.string("ZAUTHOR") ?? "", id: id, sort: r.int("ZSORT"))
            report.collections += 1
        }

        let total = max(1, (try src.query("SELECT COUNT(*) n FROM ZIJITEM")).first?.int("n") ?? 1)
        let items = try src.query("""
        SELECT ZCOLLECTION, ZNAME, ZNEWFILENAME, ZORIGINALFILENAME, ZTAGSSTRING, ZSTARRED, ZWIDTH, ZHEIGHT, ZDATE, ZLASTUSEDDATE, ZINFO, ZINFORMATIVETEXT
        FROM ZIJITEM ORDER BY ZCOLLECTION, Z_PK
        """)
        var done = 0
        var pending = 0
        try lib.db.exec("BEGIN IMMEDIATE")
        do {
            for r in items {
                done += 1
                if done % 200 == 0 { progress(Double(done) / Double(total), r.string("ZNAME") ?? "") }
                guard let c = collID[r.int("ZCOLLECTION")], let file = r.string("ZNEWFILENAME") ?? r.string("ZORIGINALFILENAME"), !file.isEmpty else { report.skipped += 1; continue }
                let from = url.appendingPathComponent("Sets").appendingPathComponent(c.sourceDir).appendingPathComponent(file)
                guard fm.fileExists(atPath: from.path) else { report.missing += 1; continue }
                let dir = lib.filesDir.appendingPathComponent(c.id)
                let to = dir.appendingPathComponent(file)
                if !fm.fileExists(atPath: to.path) { try? fm.copyItem(at: from, to: to) }
                let ext = (file as NSString).pathExtension.lowercased()
                let icon = Icon(id: UUID().uuidString, collection: c.id, name: r.string("ZNAME") ?? (file as NSString).deletingPathExtension,
                                tags: r.string("ZTAGSSTRING") ?? "", file: file, fmt: ext == "jpeg" ? "jpg" : ext, width: r.int("ZWIDTH"), height: r.int("ZHEIGHT"),
                                starred: r.int("ZSTARRED") != 0,
                                lastUsed: r.double("ZLASTUSEDDATE") > 0 ? Date(timeIntervalSinceReferenceDate: r.double("ZLASTUSEDDATE")) : nil,
                                added: r.double("ZDATE") > 0 ? Date(timeIntervalSinceReferenceDate: r.double("ZDATE")) : Date(),
                                sourceURL: "", pageURL: "", linkPath: "", info: r.string("ZINFORMATIVETEXT") ?? r.string("ZINFO") ?? "")
                try lib.insert(icon)
                report.icons += 1; pending += 1
                if pending >= 2000 { try lib.db.exec("COMMIT"); try lib.db.exec("BEGIN IMMEDIATE"); pending = 0 }
            }
            try lib.db.exec("COMMIT")
        } catch { try? lib.db.exec("ROLLBACK"); throw error }
        progress(1, "")
        return report
    }

    /// Jar sans `Jars.db` (ancien format) : on lit tous les SVG et bitmaps du paquet, un dossier = une collection.
    static func importPackage(at url: URL, into lib: Library, progress: ProgressHandler) throws -> ImportReport {
        try FolderImporter.importFolder(at: url, into: lib, groupNamed: nil, progress: progress)
    }
}

public enum FolderImporter {
    /// Importe un dossier ou des fichiers. Chaque dossier contenant des icônes devient une collection ;
    /// s'il y en a plusieurs, elles sont regroupées dans un groupe du nom du dossier choisi.
    @discardableResult
    public static func importFolder(at root: URL, into lib: Library, groupNamed: String?, progress: ProgressHandler = { _, _ in }) throws -> ImportReport {
        let fm = FileManager.default
        var byDir: [String: [URL]] = [:]
        if let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let u as URL in en where ImageMeta.supported.contains(u.pathExtension.lowercased()) {
                byDir[u.deletingLastPathComponent().path, default: []].append(u)
            }
        }
        var report = ImportReport()
        guard !byDir.isEmpty else { return report }
        let group: String? = byDir.count > 1 ? try (groupNamed.map { try lib.addGroup(name: $0).id } ?? lib.addGroup(name: root.deletingPathExtension().lastPathComponent).id) : nil
        let all = byDir.values.reduce(0) { $0 + $1.count }
        var done = 0
        for dir in byDir.keys.sorted() {
            let rel = dir == root.path ? root.deletingPathExtension().lastPathComponent : String(dir.dropFirst(root.path.count + 1))
            let coll = try lib.addCollection(name: rel.replacingOccurrences(of: "/", with: " / "), group: group)
            report.collections += 1
            try lib.db.transaction {
                for f in byDir[dir]!.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    done += 1
                    if done % 100 == 0 { progress(Double(done) / Double(all), f.lastPathComponent) }
                    guard let data = try? Data(contentsOf: f) else { report.skipped += 1; continue }
                    let ext = f.pathExtension.lowercased()
                    if (try? lib.addIcon(data: data, fmt: ext == "jpeg" ? "jpg" : ext, name: f.deletingPathExtension().lastPathComponent, collection: coll.id)) != nil { report.icons += 1 }
                    else { report.skipped += 1 }
                }
            }
        }
        progress(1, "")
        return report
    }

    /// Fichiers isolés déposés dans une collection.
    @discardableResult
    public static func importFiles(_ urls: [URL], into collection: String, lib: Library) -> ImportReport {
        var report = ImportReport()
        for f in urls {
            let ext = f.pathExtension.lowercased()
            guard ImageMeta.supported.contains(ext), let data = try? Data(contentsOf: f) else { report.skipped += 1; continue }
            if (try? lib.addIcon(data: data, fmt: ext == "jpeg" ? "jpg" : ext, name: f.deletingPathExtension().lastPathComponent, collection: collection)) != nil { report.icons += 1 }
        }
        return report
    }
}
