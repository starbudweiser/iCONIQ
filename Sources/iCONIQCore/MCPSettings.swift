import Foundation

/// Réglages du pilotage par IA (serveur MCP `iconiq-mcp`), partagés entre l'appli et l'auxiliaire : `mcp.json` (droits 600)
/// dans le dossier de données. Valeurs génériques par défaut : rien n'est propre à un utilisateur.
public struct MCPSettings: Codable, Equatable, Sendable {
    public enum ClientState: String, Codable, Sendable { case allowed, pending, denied }

    /// Règle de rangement : si le nom de l'appli ou le chemin contient `contains` (sans casse ni accents), l'icône va dans `collection`.
    public struct Rule: Codable, Equatable, Sendable, Identifiable {
        public var id = UUID().uuidString
        public var field: String = "path"         // "path" ou "name"
        public var contains: String = ""
        public var kind: String = "any"           // "app", "folder" ou "any"
        public var collection: String = ""        // identifiant de collection
        public init(field: String = "path", contains: String = "", kind: String = "any", collection: String = "") {
            self.field = field; self.contains = contains; self.kind = kind; self.collection = collection
        }
    }

    public var enabled = false
    public var clients: [String: ClientState] = [:]
    public var appCollection: String?             // collection par défaut des icônes d'appli
    public var folderCollection: String?          // collection par défaut des icônes de dossier
    public var rules: [Rule] = []
    public var folderColor = "bleu"               // clé de couleur de MiCONE ou #rrggbb
    public var engraved = false
    public var removeBackground = false
    public var backupIcons = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MCPSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        clients = try c.decodeIfPresent([String: ClientState].self, forKey: .clients) ?? [:]
        appCollection = try c.decodeIfPresent(String.self, forKey: .appCollection)
        folderCollection = try c.decodeIfPresent(String.self, forKey: .folderCollection)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        folderColor = try c.decodeIfPresent(String.self, forKey: .folderColor) ?? d.folderColor
        engraved = try c.decodeIfPresent(Bool.self, forKey: .engraved) ?? d.engraved
        removeBackground = try c.decodeIfPresent(Bool.self, forKey: .removeBackground) ?? d.removeBackground
        backupIcons = try c.decodeIfPresent(Bool.self, forKey: .backupIcons) ?? d.backupIcons
    }
}

public enum MCPStore {
    public static func url(_ root: URL = Library.defaultRoot) -> URL { root.appendingPathComponent("mcp.json") }
    public static func logURL(_ root: URL = Library.defaultRoot) -> URL { root.appendingPathComponent("mcp.log") }
    public static func backupsDir(_ root: URL = Library.defaultRoot) -> URL { root.appendingPathComponent("Backups", isDirectory: true) }
    public static func madeDir(_ root: URL = Library.defaultRoot) -> URL { root.appendingPathComponent("Made", isDirectory: true) }

    /// Notifications entre l'auxiliaire et l'appli (sans données : chacun relit les fichiers).
    public static var libraryChanged: Notification.Name { .init(Edition.isDev ? "fr.stephan.iconiq.dev.library-changed" : "fr.stephan.iconiq.library-changed") }
    public static var settingsChanged: Notification.Name { .init(Edition.isDev ? "fr.stephan.iconiq.dev.mcp-changed" : "fr.stephan.iconiq.mcp-changed") }

    public static func load(_ root: URL = Library.defaultRoot) -> MCPSettings {
        guard let d = try? Data(contentsOf: url(root)), let s = try? JSONDecoder().decode(MCPSettings.self, from: d) else { return MCPSettings() }
        return s
    }

    public static func save(_ s: MCPSettings, _ root: URL = Library.defaultRoot) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(s).write(to: url(root), options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url(root).path)
    }

    /// Modifie les réglages sous verrou de fichier (l'appli et l'auxiliaire peuvent écrire en même temps).
    @discardableResult
    public static func update(_ root: URL = Library.defaultRoot, _ change: (inout MCPSettings) -> Void) -> MCPSettings {
        let lock = root.appendingPathComponent("mcp.lock").path
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = open(lock, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        var s = load(root); change(&s); try? save(s, root)
        post(settingsChanged)
        return s
    }

    public static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    // MARK: Journal

    public static func log(_ line: String, _ root: URL = Library.defaultRoot) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let entry = "\(f.string(from: Date()))\t\(line.replacingOccurrences(of: "\n", with: " "))\n"
        var lines = (try? String(contentsOf: logURL(root), encoding: .utf8))?.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) ?? []
        lines.append(String(entry.dropLast()))
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        try? (lines.joined(separator: "\n") + "\n").write(to: logURL(root), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL(root).path)
    }

    public static func readLog(_ root: URL = Library.defaultRoot, last n: Int = 50) -> [String] {
        let lines = (try? String(contentsOf: logURL(root), encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        return Array(lines.suffix(n))
    }
}

/// Choix de la collection proposée pour une icône (règles, puis collection par défaut). Partagé par l'outil MCP et ses essais.
public enum Rangement {
    public struct Proposal: Sendable { public var collection: IconCollection?; public var reason: String }

    public static func suggest(appName: String, path: String?, kind: String, settings s: MCPSettings, collections: [IconCollection]) -> Proposal {
        let usable = collections.filter { $0.kind != .portal }
        for r in s.rules where !r.contains.isEmpty && (r.kind == "any" || r.kind == kind) {
            let hay = Norm.fold(r.field == "name" ? appName : (path ?? ""))
            if hay.contains(Norm.fold(r.contains)), let c = usable.first(where: { $0.id == r.collection }) {
                return Proposal(collection: c, reason: "rule: \(r.field) contains \"\(r.contains)\"")
            }
        }
        let def = kind == "folder" ? s.folderCollection : s.appCollection
        if let def, let c = usable.first(where: { $0.id == def }) { return Proposal(collection: c, reason: "default collection for \(kind) icons") }
        return Proposal(collection: nil, reason: "no rule or default collection set: ask the user which collection to use (library_list), or create one")
    }
}
