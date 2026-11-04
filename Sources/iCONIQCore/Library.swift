import Foundation
import CryptoKit

/// Base d'icônes d'iCONIQ : `Library.db` + fichiers dans `Files/<collection>/`.
public final class Library: @unchecked Sendable {
    public let root: URL
    public let db: Database
    public var filesDir: URL { root.appendingPathComponent("Files", isDirectory: true) }
    public var cacheDir: URL { root.appendingPathComponent("Cache", isDirectory: true) }
    public var inboxDir: URL { root.appendingPathComponent("Inbox", isDirectory: true) }

    public static var defaultRoot: URL {
        if let p = ProcessInfo.processInfo.environment["ICONIQ_DATA_DIR"] { return URL(fileURLWithPath: p, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("iCONIQ", isDirectory: true)
    }

    public init(root: URL = Library.defaultRoot) throws {
        self.root = root
        let fm = FileManager.default
        for d in [root, root.appendingPathComponent("Files"), root.appendingPathComponent("Cache"), root.appendingPathComponent("Inbox")] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        db = try Database(path: root.appendingPathComponent("Library.db").path)
        try migrate()
    }

    private func migrate() throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS groups (id TEXT PRIMARY KEY, parent TEXT, name TEXT NOT NULL, sort INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS collections (id TEXT PRIMARY KEY, grp TEXT, name TEXT NOT NULL, author TEXT DEFAULT '', source_url TEXT DEFAULT '',
            license TEXT DEFAULT '', kind TEXT DEFAULT 'normal', sort INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS icons (id TEXT PRIMARY KEY, collection TEXT NOT NULL, name TEXT NOT NULL, name_norm TEXT NOT NULL,
            tags TEXT DEFAULT '', tags_norm TEXT DEFAULT '', file TEXT NOT NULL, fmt TEXT NOT NULL, width INTEGER DEFAULT 0, height INTEGER DEFAULT 0,
            starred INTEGER DEFAULT 0, last_used REAL, added REAL NOT NULL, source_url TEXT DEFAULT '', page_url TEXT DEFAULT '',
            link_path TEXT DEFAULT '', info TEXT DEFAULT '', hash TEXT DEFAULT '');
        CREATE INDEX IF NOT EXISTS icons_collection ON icons(collection);
        CREATE INDEX IF NOT EXISTS icons_starred ON icons(starred);
        CREATE INDEX IF NOT EXISTS icons_last_used ON icons(last_used);
        CREATE INDEX IF NOT EXISTS icons_link ON icons(link_path);
        CREATE INDEX IF NOT EXISTS icons_hash ON icons(hash);
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS portals (id TEXT PRIMARY KEY, name TEXT NOT NULL, url TEXT NOT NULL, search_url TEXT DEFAULT '', sort INTEGER DEFAULT 0);
        """)
    }

    // MARK: Groupes et collections

    public func groups() -> [IconGroup] {
        ((try? db.query("SELECT * FROM groups ORDER BY sort, name COLLATE NOCASE")) ?? []).map {
            IconGroup(id: $0.string("id") ?? "", parent: $0.string("parent"), name: $0.string("name") ?? "", sort: $0.int("sort"))
        }
    }

    public func collections() -> [IconCollection] {
        let counts = Dictionary(uniqueKeysWithValues: ((try? db.query("SELECT collection, COUNT(*) n FROM icons GROUP BY collection")) ?? []).map { ($0.string("collection") ?? "", $0.int("n")) })
        return ((try? db.query("SELECT * FROM collections ORDER BY sort, name COLLATE NOCASE")) ?? []).map {
            let id = $0.string("id") ?? ""
            return IconCollection(id: id, group: $0.string("grp"), name: $0.string("name") ?? "", author: $0.string("author") ?? "",
                                  sourceURL: $0.string("source_url") ?? "", license: $0.string("license") ?? "",
                                  kind: CollectionKind(rawValue: $0.string("kind") ?? "") ?? .normal, sort: $0.int("sort"), count: counts[id] ?? 0)
        }
    }

    @discardableResult
    public func addGroup(name: String, parent: String? = nil, id: String = UUID().uuidString, sort: Int = 0) throws -> IconGroup {
        try db.run("INSERT INTO groups (id,parent,name,sort) VALUES (?,?,?,?)", [.text(id), .opt(parent), .text(name), .int(Int64(sort))])
        return IconGroup(id: id, parent: parent, name: name, sort: sort)
    }

    @discardableResult
    public func addCollection(name: String, group: String? = nil, kind: CollectionKind = .normal, author: String = "", sourceURL: String = "",
                              license: String = "", id: String = UUID().uuidString, sort: Int = 0) throws -> IconCollection {
        try db.run("INSERT INTO collections (id,grp,name,author,source_url,license,kind,sort) VALUES (?,?,?,?,?,?,?,?)",
                   [.text(id), .opt(group), .text(name), .text(author), .text(sourceURL), .text(license), .text(kind.rawValue), .int(Int64(sort))])
        try FileManager.default.createDirectory(at: filesDir.appendingPathComponent(id), withIntermediateDirectories: true)
        return IconCollection(id: id, group: group, name: name, author: author, sourceURL: sourceURL, license: license, kind: kind, sort: sort)
    }

    /// Collection « PERSONNEL » (créée au besoin) : destination des icônes venues de MiCONE.
    public func personalCollection() throws -> IconCollection {
        if let c = collections().first(where: { $0.name.caseInsensitiveCompare(Inbox.collectionName) == .orderedSame && $0.kind != .portal }) { return c }
        return try addCollection(name: Inbox.collectionName)
    }

    /// Nombre d'icônes suivies depuis MiCONE.
    public func linkedCount() -> Int { (try? db.query("SELECT COUNT(*) n FROM icons WHERE link_path<>''"))?.first?.int("n") ?? 0 }

    /// Collection existante de même nom et de même type, sinon créée.
    public func collection(named name: String, kind: CollectionKind, group: String? = nil, sourceURL: String = "") throws -> IconCollection {
        if let c = collections().first(where: { $0.name == name && $0.kind == kind && $0.group == group }) { return c }
        return try addCollection(name: name, group: group, kind: kind, sourceURL: sourceURL)
    }

    public func renameGroup(_ id: String, to name: String) { _ = try? db.run("UPDATE groups SET name=? WHERE id=?", [.text(name), .text(id)]) }
    public func renameCollection(_ id: String, to name: String) { _ = try? db.run("UPDATE collections SET name=? WHERE id=?", [.text(name), .text(id)]) }
    public func moveCollection(_ id: String, to group: String?) { _ = try? db.run("UPDATE collections SET grp=? WHERE id=?", [.opt(group), .text(id)]) }

    public func deleteCollection(_ id: String) {
        _ = try? db.run("DELETE FROM icons WHERE collection=?", [.text(id)])
        _ = try? db.run("DELETE FROM collections WHERE id=?", [.text(id)])
        try? FileManager.default.removeItem(at: filesDir.appendingPathComponent(id))
    }

    public func deleteGroup(_ id: String) {
        for c in collections() where c.group == id { deleteCollection(c.id) }
        for g in groups() where g.parent == id { deleteGroup(g.id) }
        _ = try? db.run("DELETE FROM groups WHERE id=?", [.text(id)])
    }

    // MARK: Icônes

    private static func decode(_ r: Row) -> Icon {
        Icon(id: r.string("id") ?? "", collection: r.string("collection") ?? "", name: r.string("name") ?? "", tags: r.string("tags") ?? "",
             file: r.string("file") ?? "", fmt: r.string("fmt") ?? "", width: r.int("width"), height: r.int("height"), starred: r.int("starred") != 0,
             lastUsed: r.double("last_used") > 0 ? Date(timeIntervalSinceReferenceDate: r.double("last_used")) : nil,
             added: Date(timeIntervalSinceReferenceDate: r.double("added")), sourceURL: r.string("source_url") ?? "", pageURL: r.string("page_url") ?? "",
             linkPath: r.string("link_path") ?? "", info: r.string("info") ?? "")
    }

    public func fileURL(_ icon: Icon) -> URL { filesDir.appendingPathComponent(icon.collection).appendingPathComponent(icon.file) }

    public func icons(_ q: IconQuery, limit: Int = 100_000) -> [Icon] {
        var wh: [String] = [], args: [SQLValue] = []
        switch q.scope {
        case .all: break
        case .starred: wh.append("starred=1")
        case .recent: wh.append("last_used IS NOT NULL")
        case .micone: wh.append("link_path<>''")
        case .collection(let id): wh.append("collection=?"); args.append(.text(id))
        case .group(let id):
            let ids = collectionIDs(inGroup: id)
            wh.append("collection IN (\(ids.map { _ in "?" }.joined(separator: ",")))"); args += ids.map { .text($0) }
            if ids.isEmpty { return [] }
        }
        for token in Norm.fold(q.text).split(whereSeparator: { $0 == " " }) {
            wh.append("(name_norm LIKE ? OR tags_norm LIKE ?)")
            args += [.text("%\(token)%"), .text("%\(token)%")]
        }
        let order: String
        if case .recent = q.scope { order = "last_used DESC" }
        else {
            switch q.sort {
            case .name: order = "name_norm, id"
            case .added: order = "added DESC, name_norm"
            case .size: order = "width*height DESC, name_norm"
            }
        }
        let sql = "SELECT * FROM icons \(wh.isEmpty ? "" : "WHERE " + wh.joined(separator: " AND ")) ORDER BY \(order) LIMIT \(limit)"
        return ((try? db.query(sql, args)) ?? []).map(Self.decode)
    }

    public func icon(id: String) -> Icon? { (try? db.query("SELECT * FROM icons WHERE id=?", [.text(id)]))?.first.map(Self.decode) }

    public func collectionIDs(inGroup id: String) -> [String] {
        let gs = groups(), cs = collections()
        var gids: Set<String> = [id], changed = true
        while changed { changed = false; for g in gs where g.parent != nil && gids.contains(g.parent!) && !gids.contains(g.id) { gids.insert(g.id); changed = true } }
        return cs.filter { $0.group != nil && gids.contains($0.group!) }.map(\.id)
    }

    public func totalCount() -> Int { (try? db.query("SELECT COUNT(*) n FROM icons"))?.first?.int("n") ?? 0 }

    public func existing(hash: String, in collection: String) -> Icon? {
        guard !hash.isEmpty else { return nil }
        return (try? db.query("SELECT * FROM icons WHERE hash=? AND collection=? LIMIT 1", [.text(hash), .text(collection)]))?.first.map(Self.decode)
    }

    public func icon(linkPath: String) -> Icon? {
        (try? db.query("SELECT * FROM icons WHERE link_path=? LIMIT 1", [.text(linkPath)]))?.first.map(Self.decode)
    }

    /// Nom de fichier libre dans la collection (suffixe -2, -3… en cas de doublon).
    func uniqueFileName(_ base: String, ext: String, collection: String) -> String {
        let dir = filesDir.appendingPathComponent(collection)
        var name = "\(base).\(ext)", n = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) { name = "\(base)-\(n).\(ext)"; n += 1 }
        return name
    }

    public static func fileSafe(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|\0").union(.controlCharacters)
        let t = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String(t.prefix(80)).isEmpty ? "icon" : String(t.prefix(80))
    }

    /// Ajoute une icône à partir de ses octets (capture web, MiCONE, import de fichiers).
    @discardableResult
    public func addIcon(data: Data, fmt: String, name: String, tags: String = "", collection: String, sourceURL: String = "", pageURL: String = "",
                        linkPath: String = "", info: String = "", skipDuplicate: Bool = true) throws -> Icon {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if skipDuplicate, let dup = existing(hash: hash, in: collection) { return dup }
        let file = uniqueFileName(Self.fileSafe(name), ext: fmt, collection: collection)
        let dir = filesDir.appendingPathComponent(collection)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(file), options: .atomic)
        let size = ImageMeta.size(data: data, fmt: fmt)
        return try insert(Icon(id: UUID().uuidString, collection: collection, name: name, tags: tags, file: file, fmt: fmt, width: size.width, height: size.height,
                               starred: false, lastUsed: nil, added: Date(), sourceURL: sourceURL, pageURL: pageURL, linkPath: linkPath, info: info), hash: hash)
    }

    @discardableResult
    public func insert(_ i: Icon, hash: String = "") throws -> Icon {
        try db.run("""
        INSERT INTO icons (id,collection,name,name_norm,tags,tags_norm,file,fmt,width,height,starred,last_used,added,source_url,page_url,link_path,info,hash)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, [.text(i.id), .text(i.collection), .text(i.name), .text(Norm.fold(i.name)), .text(i.tags), .text(Norm.fold(i.tags)), .text(i.file), .text(i.fmt),
              .int(Int64(i.width)), .int(Int64(i.height)), .int(i.starred ? 1 : 0), i.lastUsed.map { .double($0.timeIntervalSinceReferenceDate) } ?? .null,
              .double(i.added.timeIntervalSinceReferenceDate), .text(i.sourceURL), .text(i.pageURL), .text(i.linkPath), .text(i.info), .text(hash)])
        return i
    }

    /// Remplace le contenu d'une icône suivie (nouvel export MiCONE) en gardant son identité, ses étiquettes et ses favoris.
    public func replaceData(of icon: Icon, data: Data, fmt: String) throws {
        let dir = filesDir.appendingPathComponent(icon.collection)
        let newFile = fmt == icon.fmt ? icon.file : uniqueFileName(Self.fileSafe(icon.name), ext: fmt, collection: icon.collection)
        try data.write(to: dir.appendingPathComponent(newFile), options: .atomic)
        if newFile != icon.file { try? FileManager.default.removeItem(at: dir.appendingPathComponent(icon.file)) }
        let size = ImageMeta.size(data: data, fmt: fmt)
        try db.run("UPDATE icons SET file=?, fmt=?, width=?, height=?, added=? WHERE id=?",
                   [.text(newFile), .text(fmt), .int(Int64(size.width)), .int(Int64(size.height)), .double(Date().timeIntervalSinceReferenceDate), .text(icon.id)])
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("thumbs"))
    }

    public func update(_ id: String, name: String? = nil, tags: String? = nil, collection: String? = nil) {
        if let name { _ = try? db.run("UPDATE icons SET name=?, name_norm=? WHERE id=?", [.text(name), .text(Norm.fold(name)), .text(id)]) }
        if let tags { _ = try? db.run("UPDATE icons SET tags=?, tags_norm=? WHERE id=?", [.text(tags), .text(Norm.fold(tags)), .text(id)]) }
        if let collection, let i = icon(id: id), i.collection != collection {
            let dest = filesDir.appendingPathComponent(collection)
            let newFile = uniqueFileName((i.file as NSString).deletingPathExtension, ext: i.fmt, collection: collection)
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            if (try? FileManager.default.moveItem(at: fileURL(i), to: dest.appendingPathComponent(newFile))) != nil {
                _ = try? db.run("UPDATE icons SET collection=?, file=? WHERE id=?", [.text(collection), .text(newFile), .text(id)])
            }
        }
    }

    public func setStarred(_ ids: [String], _ on: Bool) {
        for id in ids { _ = try? db.run("UPDATE icons SET starred=? WHERE id=?", [.int(on ? 1 : 0), .text(id)]) }
    }

    public func touch(_ ids: [String]) {
        let now = Date().timeIntervalSinceReferenceDate
        for id in ids { _ = try? db.run("UPDATE icons SET last_used=? WHERE id=?", [.double(now), .text(id)]) }
    }

    public func delete(_ ids: [String]) {
        for id in ids {
            if let i = icon(id: id) { try? FileManager.default.removeItem(at: fileURL(i)) }
            _ = try? db.run("DELETE FROM icons WHERE id=?", [.text(id)])
        }
    }

    // MARK: Portails

    public func portals() -> [Portal] {
        ((try? db.query("SELECT * FROM portals ORDER BY sort, name COLLATE NOCASE")) ?? []).map {
            Portal(id: $0.string("id") ?? "", name: $0.string("name") ?? "", url: $0.string("url") ?? "", searchURL: $0.string("search_url") ?? "", sort: $0.int("sort"))
        }
    }

    @discardableResult
    public func savePortal(_ p: Portal) -> Portal {
        _ = try? db.run("INSERT OR REPLACE INTO portals (id,name,url,search_url,sort) VALUES (?,?,?,?,?)",
                        [.text(p.id), .text(p.name), .text(p.url), .text(p.searchURL), .int(Int64(p.sort))])
        return p
    }

    public func deletePortal(_ id: String) { _ = try? db.run("DELETE FROM portals WHERE id=?", [.text(id)]) }

    /// Portails proposés au premier lancement (modifiables et supprimables).
    public func seedPortalsIfNeeded() {
        guard (try? db.query("SELECT value FROM meta WHERE key='portalsSeeded'"))?.isEmpty == true else { return }
        _ = try? db.run("INSERT INTO meta (key,value) VALUES ('portalsSeeded','1')")
        guard (try? db.query("SELECT COUNT(*) n FROM portals"))?.first?.int("n") == 0 else { return }
        for (i, d) in PortalDefaults.all.enumerated() {
            savePortal(Portal(id: UUID().uuidString, name: d.name, url: d.url, searchURL: d.search, sort: i))
        }
    }
}

public enum PortalDefaults {
    public static let all: [(name: String, url: String, search: String)] = [
        ("SVG Repo", "https://www.svgrepo.com/", "https://www.svgrepo.com/vectors/{q}/"),
        ("Iconify", "https://icon-sets.iconify.design/", "https://icon-sets.iconify.design/?query={q}"),
        ("Lucide", "https://lucide.dev/icons/", "https://lucide.dev/icons/?search={q}"),
        ("Phosphor", "https://phosphoricons.com/", "https://phosphoricons.com/?q={q}"),
        ("Tabler Icons", "https://tabler.io/icons", "https://tabler.io/icons?q={q}"),
        ("Flaticon", "https://www.flaticon.com/", "https://www.flaticon.com/search?word={q}"),
        ("Icons8", "https://icons8.com/icons", "https://icons8.com/icons/set/{q}"),
    ]
}
