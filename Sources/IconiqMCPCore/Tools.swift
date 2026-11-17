import AppKit
import Foundation
import iCONIQCore
import MiCONECore

/// Outils du serveur MCP : `icons_*` (fabrication et pose, moteur de MiCONE) et `library_*` (bibliothèque d'iCONIQ).
struct Tools {
    let server: MCPServer
    var root: URL { server.root }

    static let names: Set<String> = Set(schemas.compactMap { $0["name"] as? String })

    // MARK: Schémas

    static let schemas: [[String: Any]] = {
        func tool(_ name: String, _ description: String, _ props: [String: Any], _ required: [String] = []) -> [String: Any] {
            ["name": name, "description": description, "inputSchema": ["type": "object", "properties": props, "required": required]]
        }
        let s: [String: Any] = ["type": "string"], b: [String: Any] = ["type": "boolean"], n: [String: Any] = ["type": "integer"]
        func d(_ base: [String: Any], _ text: String) -> [String: Any] { var x = base; x["description"] = text; return x }
        let kind = d(["type": "string", "enum": ["app", "folder"]], "app = squircle application icon, folder = Finder-style folder icon.")
        let color = d(s, "Folder colour: bleu, graphite, nuit, clair, or #rrggbb. Default: the colour chosen in iCONIQ's settings.")
        return [
            tool("icons_make", "Make a macOS icon (.icns + 1024 px PNG) from an image with MiCONE's engine. Returns the file paths and a preview.", [
                "image": d(s, "Source image (PNG, JPEG, SVG, ICNS…)."), "kind": kind, "folder_color": color,
                "engraved": d(b, "Folder: engrave the motif in the folder colour instead of keeping its colours. Default from settings."),
                "background": d(s, "App icon background: sombre (default), graphite, nuit, clair, or #rrggbb."),
                "remove_background": d(b, "Remove the image background first (Apple Vision, on this Mac). Default from settings."),
                "size": d(n, "Motif size in % of the shape (default 72)."), "offset_y": d(n, "Vertical offset in % (default 0)."),
                "output_dir": d(s, "Folder for the files. Default: iCONIQ's Made/<name> folder."), "name": d(s, "File name (default: the image name)."),
            ], ["image", "kind"]),
            tool("icons_apply_to_folder", "Set a custom Finder icon on a folder. The previous custom icon is backed up. System folders, Applications, app bundles and disk roots are refused.", [
                "folder": d(s, "Folder to dress."), "icon": d(s, "Icon file (.icns or image)."), "icon_id": d(s, "Or the id of an icon of the iCONIQ library."),
            ], ["folder"]),
            tool("icons_clear_folder_icon", "Remove the custom Finder icon of a folder (backed up first).", ["folder": d(s, "Folder.")], ["folder"]),
            tool("icons_app_kit", "One call for a new app: makes the app icon and the Finder-style folder icon from the app image, sets the folder icon on the app's folder and files both icons in the library. Confirm the collections with the user first (library_suggest_collection).", [
                "image": d(s, "The app's 1024 px icon image."), "app_name": d(s, "App name (icon names)."),
                "folder": d(s, "The app's folder to dress (optional)."), "apply": d(b, "Set the folder icon on `folder` (default true when folder is given)."),
                "collection_app": d(s, "Collection (id or exact name) for the app icon. Default: suggestion."),
                "collection_folder": d(s, "Collection (id or exact name) for the folder icon. Default: suggestion."),
                "folder_color": color, "engraved": d(b, "Engrave the motif (default from settings)."),
                "remove_background": d(b, "Remove the image background first (default from settings)."),
                "output_dir": d(s, "Folder for the files. Default: iCONIQ's Made/<app_name> folder."),
            ], ["image", "app_name"]),
            tool("library_list", "Groups and collections of the iCONIQ library (ids, names, icon counts).", [:]),
            tool("library_suggest_collection", "Collection proposed for an app's icon by the user's rules and defaults, with the reason. Show it to the user as the preselected choice.", [
                "app_name": d(s, "App name."), "path": d(s, "App folder (rules can match the path)."), "kind": kind,
            ], ["app_name", "kind"]),
            tool("library_create_collection", "Create a collection (or return the existing one with the same name in the same group).", [
                "name": d(s, "Collection name."), "group": d(s, "Group id or exact name (optional)."),
            ], ["name"]),
            tool("library_create_group", "Create a group (or return the existing one with the same name under the same parent).", [
                "name": d(s, "Group name."), "parent": d(s, "Parent group id or exact name (optional)."),
            ], ["name"]),
            tool("library_add_icon", "Add an icon file to a collection. With `origin`, an icon already added from the same origin is updated in place.", [
                "file": d(s, "Icon file (PNG, SVG, ICNS…)."), "name": d(s, "Icon name."), "collection": d(s, "Collection id or exact name."),
                "tags": d(s, "Comma-separated tags."), "kind": d(s, "app, folder or other (added to the tags)."), "origin": d(s, "Stable identity of the icon (e.g. the source image path)."),
            ], ["file", "name", "collection"]),
            tool("library_search", "Search icons by name and tags.", [
                "query": d(s, "Words to look for."), "collection": d(s, "Collection id or exact name."), "starred": d(b, "Favourites only."),
                "limit": d(n, "Maximum results (default 50, max 500)."),
            ]),
            tool("library_get_icon", "Details of an icon, its file path and a preview; optionally export it as PNG.", [
                "id": d(s, "Icon id."), "export_png": d(n, "Export size in px (optional)."), "dest": d(s, "Export folder (default: Made/exports)."),
            ], ["id"]),
        ]
    }()

    // MARK: Exécution

    func run(_ name: String, _ a: [String: Any]) throws -> (Any, [Data]) {
        switch name {
        case "icons_make": return try make(a)
        case "icons_apply_to_folder": return try applyToFolder(a)
        case "icons_clear_folder_icon": return try clearFolder(a)
        case "icons_app_kit": return try appKit(a)
        case "library_list": return (try list(), [])
        case "library_suggest_collection": return (try suggest(a), [])
        case "library_create_collection": return (try createCollection(a), [])
        case "library_create_group": return (try createGroup(a), [])
        case "library_add_icon": return (try addIcon(a), [])
        case "library_search": return try search(a)
        case "library_get_icon": return try getIcon(a)
        default: throw MCPError("Unknown tool: \(name)")
        }
    }

    // MARK: Paramètres

    private func str(_ a: [String: Any], _ k: String) -> String? {
        guard let v = a[k] as? String else { return nil }
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
    }
    private func need(_ a: [String: Any], _ k: String) throws -> String { guard let v = str(a, k) else { throw MCPError("\(k) is required.") }; return v }
    private func bool(_ a: [String: Any], _ k: String) -> Bool? { a[k] as? Bool }
    private func int(_ a: [String: Any], _ k: String) -> Int? { (a[k] as? Int) ?? (a[k] as? Double).map { Int($0) } ?? (a[k] as? String).flatMap { Int($0) } }
    private func path(_ p: String) -> String { ((p as NSString).expandingTildeInPath as NSString).standardizingPath }

    /// Image source lisible et raisonnable (50 Mo au plus).
    private func sourceImage(_ p: String) throws -> String {
        let f = path(p)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: f), (attrs[.type] as? FileAttributeType) == .typeRegular else { throw MCPError("Image not found: \(f)") }
        guard ((attrs[.size] as? NSNumber)?.intValue ?? 0) <= 50_000_000 else { throw MCPError("Image too large (50 MB max): \(f)") }
        return f
    }

    // MARK: Fabrication

    private func reglages(_ a: [String: Any], kind: String, settings s: MCPSettings) throws -> Reglages {
        var r = Reglages()
        r.type = kind == "folder" ? "dossier" : "appli"
        r.detourer = bool(a, "remove_background") ?? s.removeBackground
        if kind == "folder" {
            r.grave = bool(a, "engraved") ?? s.engraved
            let c = str(a, "folder_color") ?? s.folderColor
            if !Fabrique.couleurDossier(c, dans: &r) { throw MCPError("Unknown folder_color \"\(c)\": use \(Fabrique.couleursDossier.joined(separator: ", ")) or #rrggbb.") }
        } else if let bg = str(a, "background") {
            if bg.hasPrefix("#") { r.fond = "perso"; r.couleur = bg } else { r.fond = bg }
        }
        if let t = int(a, "size") { r.taille = max(10, min(100, t)) }
        if let o = int(a, "offset_y") { r.decalageY = max(-40, min(40, o)) }
        return r
    }

    private func outputDir(_ a: [String: Any], name: String) throws -> String {
        let dir = str(a, "output_dir").map(path) ?? MCPStore.madeDir(root).appendingPathComponent(Library.fileSafe(name)).path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Rend et écrit l'icône ; renvoie (chemin .icns, chemin PNG 1024, image).
    private func render(_ image: String, _ r: Reglages, dir: String, file: String) throws -> (String, String, CGImage) {
        let icone = try Fabrique.icone(image, r)
        let icns = try Rendu.exporterICNS(icone, destination: (dir as NSString).appendingPathComponent(Library.fileSafe(file) + ".icns"))
        let png = (dir as NSString).appendingPathComponent(Library.fileSafe(file) + ".png")
        try Rendu.ecrirePNG(icone, URL(fileURLWithPath: png))
        return (icns, png, icone)
    }

    private func preview(_ img: CGImage) -> Data? { Rendu.pngData(Rendu.reduire(img, 256)) }

    private func make(_ a: [String: Any]) throws -> (Any, [Data]) {
        let image = try sourceImage(try need(a, "image"))
        let kind = try need(a, "kind")
        guard ["app", "folder"].contains(kind) else { throw MCPError("kind must be app or folder.") }
        let name = str(a, "name") ?? ((image as NSString).lastPathComponent as NSString).deletingPathExtension
        let r = try reglages(a, kind: kind, settings: MCPStore.load(root))
        let (icns, png, img) = try render(image, r, dir: try outputDir(a, name: name), file: kind == "folder" ? name + " folder" : name)
        return (["icns": icns, "png": png, "kind": kind], [preview(img)].compactMap { $0 })
    }

    // MARK: Pose sur un dossier

    /// Refuse les emplacements dangereux ; renvoie le chemin réel du dossier.
    static func checkFolder(_ raw: String) throws -> String {
        let f = (URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).resolvingSymlinksInPath().path as NSString).standardizingPath
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: f, isDirectory: &dir), dir.boolValue else { throw MCPError("Folder not found: \(f)") }
        let home = NSHomeDirectory()
        let comps = (f as NSString).pathComponents
        let refused = ["/", home, "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/private", "/opt", "/cores", "/Volumes",
                       home + "/Library", home + "/Applications"]
        if refused.contains(f) || comps.contains(where: { $0.lowercased().hasSuffix(".app") || $0.lowercased().hasSuffix(".bundle") || $0.lowercased().hasSuffix(".framework") }) {
            throw MCPError("Refused: \(f) is a protected location (system folder, Applications, app bundle or disk root).")
        }
        for p in ["/System/", "/Library/", "/Applications/", "/usr/", "/bin/", "/sbin/", "/private/", "/opt/", home + "/Library/", home + "/Applications/"] where f.hasPrefix(p) {
            throw MCPError("Refused: \(f) is inside a protected location (\(p.dropLast())).")
        }
        if comps.count == 3 && comps[1] == "Volumes" { throw MCPError("Refused: \(f) is the root of a disk.") }
        guard FileManager.default.isWritableFile(atPath: f) else { throw MCPError("Folder is not writable: \(f)") }
        return f
    }

    /// Sauvegarde l'icône personnalisée actuelle du dossier (s'il en a une) ; renvoie le chemin de la sauvegarde.
    private func backup(_ folder: String) -> String? {
        guard MCPStore.load(root).backupIcons, FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent("Icon\r")) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: folder)
        img.size = NSSize(width: 1024, height: 1024)
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil), let data = Rendu.pngData(cg) else { return nil }
        let dir = MCPStore.backupsDir(root)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let out = dir.appendingPathComponent("\(f.string(from: Date())) \(Library.fileSafe((folder as NSString).lastPathComponent)).png")
        try? data.write(to: out)
        return out.path
    }

    private func setIcon(_ img: NSImage?, _ folder: String) throws {
        guard NSWorkspace.shared.setIcon(img, forFile: folder, options: []) else { throw MCPError("macOS refused to change the icon of \(folder).") }
    }

    private func applyToFolder(_ a: [String: Any]) throws -> (Any, [Data]) {
        let folder = try Self.checkFolder(try need(a, "folder"))
        let file: String
        if let id = str(a, "icon_id") {
            let l = try server.library()
            guard let icon = l.icon(id: id) else { throw MCPError("No icon with id \(id).") }
            file = l.fileURL(icon).path
        } else { file = try sourceImage(try need(a, "icon")) }
        guard let img = NSImage(contentsOfFile: file) else { throw MCPError("Unreadable icon: \(file)") }
        let saved = backup(folder)
        try setIcon(img, folder)
        var out: [String: Any] = ["folder": folder, "icon": file, "applied": true]
        if let saved { out["previous_icon_backup"] = saved }
        return (out, [])
    }

    private func clearFolder(_ a: [String: Any]) throws -> (Any, [Data]) {
        let folder = try Self.checkFolder(try need(a, "folder"))
        let saved = backup(folder)
        try setIcon(nil, folder)
        var out: [String: Any] = ["folder": folder, "cleared": true]
        if let saved { out["previous_icon_backup"] = saved }
        return (out, [])
    }

    // MARK: Nouvelle appli

    private func appKit(_ a: [String: Any]) throws -> (Any, [Data]) {
        let image = try sourceImage(try need(a, "image"))
        let appName = try need(a, "app_name")
        let s = MCPStore.load(root)
        let folder = try str(a, "folder").map { try Self.checkFolder($0) }
        let l = try server.library()
        let colls = l.collections()
        func target(_ key: String, kind: String) throws -> IconCollection {
            if let v = str(a, key) { return try resolveCollection(v, in: colls) }
            guard let c = Rangement.suggest(appName: appName, path: folder, kind: kind, settings: s, collections: colls).collection else {
                throw MCPError("No collection for the \(kind) icon: pass \(key) (ask the user; see library_list), or set a default in iCONIQ › Settings › AI control.")
            }
            return c
        }
        let cApp = try target("collection_app", kind: "app"), cFolder = try target("collection_folder", kind: "folder")
        let dir = try outputDir(a, name: appName)
        let (icnsApp, pngApp, imgApp) = try render(image, try reglages(a, kind: "app", settings: s), dir: dir, file: appName)
        let (icnsFolder, pngFolder, imgFolder) = try render(image, try reglages(a, kind: "folder", settings: s), dir: dir, file: appName + " folder")
        var out: [String: Any] = ["app_icon": ["icns": icnsApp, "png": pngApp], "folder_icon": ["icns": icnsFolder, "png": pngFolder]]
        if let folder, bool(a, "apply") ?? true {
            let saved = backup(folder)
            try setIcon(NSImage(cgImage: imgFolder, size: NSSize(width: 1024, height: 1024)), folder)
            out["folder_dressed"] = folder
            if let saved { out["previous_icon_backup"] = saved }
        }
        let iApp = try store(l, file: pngApp, name: appName, collection: cApp, kind: "app", origin: image + "#app")
        let iFolder = try store(l, file: pngFolder, name: appName, collection: cFolder, kind: "folder", origin: image + "#folder")
        server.libraryChanged()
        out["library"] = [["id": iApp.id, "kind": "app", "collection": cApp.name], ["id": iFolder.id, "kind": "folder", "collection": cFolder.name]]
        return (out, [preview(imgApp), preview(imgFolder)].compactMap { $0 })
    }

    // MARK: Bibliothèque

    private func resolveCollection(_ v: String, in colls: [IconCollection]) throws -> IconCollection {
        let usable = colls.filter { $0.kind != .portal }
        if let c = usable.first(where: { $0.id == v }) { return c }
        let same = usable.filter { $0.name == v }
        if same.count == 1 { return same[0] }
        let folded = usable.filter { Norm.fold($0.name) == Norm.fold(v) }
        if folded.count == 1 { return folded[0] }
        if same.count + folded.count > 1 { throw MCPError("Several collections are named \"\(v)\": use the id. " + Self.describe((same.isEmpty ? folded : same))) }
        throw MCPError("No collection \"\(v)\". Use library_list, or library_create_collection.")
    }

    private func resolveGroup(_ v: String, in groups: [IconGroup]) throws -> IconGroup {
        if let g = groups.first(where: { $0.id == v }) { return g }
        let same = groups.filter { Norm.fold($0.name) == Norm.fold(v) }
        if same.count == 1 { return same[0] }
        if same.count > 1 { throw MCPError("Several groups are named \"\(v)\": use the id (\(same.map(\.id).joined(separator: ", "))).") }
        throw MCPError("No group \"\(v)\". Use library_list, or library_create_group.")
    }

    private static func describe(_ cs: [IconCollection]) -> String { cs.map { "\($0.name) [\($0.id)]" }.joined(separator: ", ") }

    @discardableResult
    private func store(_ l: Library, file: String, name: String, collection: IconCollection, kind: String?, tags: String? = nil, origin: String?) throws -> Icon {
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        guard let fmt = ImageMeta.sniff(data, hint: (file as NSString).pathExtension) else { throw MCPError("Unsupported icon file: \(file)") }
        let allTags = [tags, kind].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if let origin, let old = l.icon(linkPath: origin) {
            try l.replaceData(of: old, data: data, fmt: fmt)
            l.update(old.id, name: name, collection: old.collection == collection.id ? nil : collection.id)
            return l.icon(id: old.id) ?? old
        }
        return try l.addIcon(data: data, fmt: fmt, name: name, tags: allTags, collection: collection.id, linkPath: origin ?? "", info: "MCP · \(server.clientName)", skipDuplicate: false)
    }

    private func list() throws -> Any {
        let l = try server.library()
        let colls = l.collections().filter { $0.kind != .portal }
        func coll(_ c: IconCollection) -> [String: Any] { ["id": c.id, "name": c.name, "icons": c.count] }
        func group(_ g: IconGroup, _ all: [IconGroup]) -> [String: Any] {
            ["id": g.id, "name": g.name, "groups": all.filter { $0.parent == g.id }.map { group($0, all) }, "collections": colls.filter { $0.group == g.id }.map(coll)]
        }
        let groups = l.groups()
        return ["groups": groups.filter { $0.parent == nil }.map { group($0, groups) }, "collections_without_group": colls.filter { $0.group == nil }.map(coll)]
    }

    private func suggest(_ a: [String: Any]) throws -> Any {
        let kind = try need(a, "kind")
        let p = Rangement.suggest(appName: try need(a, "app_name"), path: str(a, "path").map(path), kind: kind, settings: MCPStore.load(root), collections: try server.library().collections())
        var out: [String: Any] = ["kind": kind, "reason": p.reason]
        if let c = p.collection { out["collection"] = ["id": c.id, "name": c.name] }
        return out
    }

    private func createCollection(_ a: [String: Any]) throws -> Any {
        let l = try server.library()
        let name = try need(a, "name")
        let g = try str(a, "group").map { try resolveGroup($0, in: l.groups()) }
        if let c = l.collections().first(where: { $0.kind != .portal && $0.group == g?.id && Norm.fold($0.name) == Norm.fold(name) }) {
            return ["id": c.id, "name": c.name, "created": false]
        }
        let c = try l.addCollection(name: name, group: g?.id, sort: l.collections().count)
        server.libraryChanged()
        return ["id": c.id, "name": c.name, "created": true]
    }

    private func createGroup(_ a: [String: Any]) throws -> Any {
        let l = try server.library()
        let name = try need(a, "name")
        let groups = l.groups()
        let parent = try str(a, "parent").map { try resolveGroup($0, in: groups) }
        if let g = groups.first(where: { $0.parent == parent?.id && Norm.fold($0.name) == Norm.fold(name) }) { return ["id": g.id, "name": g.name, "created": false] }
        let g = try l.addGroup(name: name, parent: parent?.id, sort: groups.count)
        server.libraryChanged()
        return ["id": g.id, "name": g.name, "created": true]
    }

    private func addIcon(_ a: [String: Any]) throws -> Any {
        let l = try server.library()
        let file = try sourceImage(try need(a, "file"))
        let c = try resolveCollection(try need(a, "collection"), in: l.collections())
        let icon = try store(l, file: file, name: try need(a, "name"), collection: c, kind: str(a, "kind"), tags: str(a, "tags"), origin: str(a, "origin"))
        server.libraryChanged()
        return ["id": icon.id, "name": icon.name, "collection": c.name, "file": l.fileURL(icon).path]
    }

    private func iconInfo(_ l: Library, _ i: Icon, _ names: [String: String]) -> [String: Any] {
        ["id": i.id, "name": i.name, "collection": names[i.collection] ?? i.collection, "tags": i.tags, "format": i.fmt,
         "size": "\(i.width)x\(i.height)", "starred": i.starred, "file": l.fileURL(i).path]
    }

    private func search(_ a: [String: Any]) throws -> (Any, [Data]) {
        let l = try server.library()
        let colls = l.collections()
        var q = IconQuery(text: str(a, "query") ?? "")
        if let c = str(a, "collection") { q.scope = .collection(try resolveCollection(c, in: colls).id) }
        else if bool(a, "starred") == true { q.scope = .starred }
        let limit = max(1, min(500, int(a, "limit") ?? 50))
        let names = Dictionary(uniqueKeysWithValues: colls.map { ($0.id, $0.name) })
        let found = l.icons(q, limit: limit)
        return (["count": found.count, "icons": found.map { iconInfo(l, $0, names) }], [])
    }

    private func getIcon(_ a: [String: Any]) throws -> (Any, [Data]) {
        let l = try server.library()
        let id = try need(a, "id")
        guard let i = l.icon(id: id) else { throw MCPError("No icon with id \(id).") }
        var out = iconInfo(l, i, Dictionary(uniqueKeysWithValues: l.collections().map { ($0.id, $0.name) }))
        let url = l.fileURL(i)
        let cg = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if let size = int(a, "export_png") {
            guard let cg else { throw MCPError("This icon cannot be exported as PNG.") }
            let dir = str(a, "dest").map(path) ?? MCPStore.madeDir(root).appendingPathComponent("exports").path
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let dest = (dir as NSString).appendingPathComponent("\(Library.fileSafe(i.name))-\(size).png")
            try Rendu.ecrirePNG(Rendu.reduire(cg, max(16, min(2048, size))), URL(fileURLWithPath: dest))
            out["exported"] = dest
        }
        return (out, [cg.flatMap { preview($0) }].compactMap { $0 })
    }
}
