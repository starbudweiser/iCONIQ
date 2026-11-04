import Foundation

/// Lien dynamique avec MiCONE : MiCONE dépose dans `Inbox/` le fichier exporté et un descripteur `.json` ; iCONIQ l'ajoute
/// (ou met à jour l'icône déjà suivie pour le même fichier d'origine) dans la collection « PERSONNEL ».
public enum Inbox {
    public struct Request: Codable, Sendable {
        public var name: String
        public var file: String           // fichier dans Inbox/ (.icns ou .png)
        public var origin: String         // chemin de l'export dans MiCONE (identité du lien)
        public var kind: String?          // "app" ou "folder"
        public var source: String?
    }

    public static let collectionName = "PERSONNEL"
    private static let lock = NSLock()   // les surveillances du dossier peuvent se chevaucher : un seul traitement à la fois

    /// Traite tous les descripteurs en attente ; renvoie les identifiants d'icônes ajoutées ou mises à jour.
    @discardableResult
    public static func process(_ lib: Library) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: lib.inboxDir.path) else { return [] }
        var ids: [String] = []
        for n in names.sorted() where n.hasSuffix(".json") {
            let jsonURL = lib.inboxDir.appendingPathComponent(n)
            guard let d = try? Data(contentsOf: jsonURL), let req = try? JSONDecoder().decode(Request.self, from: d) else { try? fm.removeItem(at: jsonURL); continue }
            let fileURL = lib.inboxDir.appendingPathComponent(req.file)
            guard let data = try? Data(contentsOf: fileURL), let fmt = ImageMeta.sniff(data, hint: (req.file as NSString).pathExtension) else { try? fm.removeItem(at: jsonURL); continue }
            do {
                if let old = lib.icon(linkPath: req.origin) {
                    try lib.replaceData(of: old, data: data, fmt: fmt)
                    ids.append(old.id)
                } else {
                    let coll = try lib.personalCollection()
                    let kind = req.kind == "folder" ? "folder" : "app"
                    let icon = try lib.addIcon(data: data, fmt: fmt, name: req.name, tags: "MiCONE, \(kind)", collection: coll.id, linkPath: req.origin, info: req.source ?? "MiCONE", skipDuplicate: false)
                    ids.append(icon.id)
                }
                try? fm.removeItem(at: fileURL); try? fm.removeItem(at: jsonURL)
            } catch { /* laissé en place : nouvel essai au prochain passage */ }
        }
        return ids
    }

    /// Dépose une demande (utilisé par les essais ; MiCONE écrit le même format).
    public static func submit(_ req: Request, data: Data, lib: Library) throws {
        let stem = UUID().uuidString
        let ext = (req.file as NSString).pathExtension
        var r = req; r.file = "\(stem).\(ext)"
        try data.write(to: lib.inboxDir.appendingPathComponent(r.file))
        try JSONEncoder().encode(r).write(to: lib.inboxDir.appendingPathComponent("\(stem).json"), options: .atomic)
    }
}
