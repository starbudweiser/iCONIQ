import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import iCONIQCore

enum SidebarItem: Hashable {
    case all, starred, recent, micone
    case group(String), collection(String), portal(String)
}

struct Toast: Equatable { var id = UUID(); var text: String; var error = false }

struct ImportProgress { var title: String; var fraction: Double; var detail: String }

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    let lib: Library

    @Published var item: SidebarItem = .all { didSet { if item != oldValue { selection = []; reload() } } }
    @Published var search = "" { didSet { if search != oldValue { debounceReload() } } }
    @Published var sort: IconSort = .name { didSet { reload() } }
    @Published private(set) var icons: [Icon] = []
    @Published var selection: Set<String> = []
    @Published var groups: [IconGroup] = []
    @Published var collections: [IconCollection] = []
    @Published var portals: [Portal] = []
    @Published var total = 0
    @Published var expanded: Set<String> = []
    @Published var progress: ImportProgress?
    @Published var toast: Toast?
    @Published var portalSheet: Portal?
    @Published var inspectorOpen = true

    private var generation = 0
    private var controllers: [String: PortalController] = [:]
    private var debounce: Task<Void, Never>?
    private var inboxSource: DispatchSourceFileSystemObject?
    private var anchor: String?

    init() {
        do { lib = try Library() } catch { fatalError("Bibliothèque illisible : \(error)") }
        lib.seedPortalsIfNeeded()
        refreshSidebar()
        reload()
    }

    // MARK: Données

    func refreshSidebar() {
        groups = lib.groups(); collections = lib.collections(); portals = lib.portals(); total = lib.totalCount()
    }

    var query: IconQuery? {
        let scope: Scope
        switch item {
        case .all: scope = .all
        case .starred: scope = .starred
        case .recent: scope = .recent
        case .micone: scope = .micone
        case .group(let id): scope = .group(id)
        case .collection(let id): scope = .collection(id)
        case .portal: return nil
        }
        return IconQuery(scope: scope, text: search, sort: sort)
    }

    func reload() {
        refreshSidebar()
        guard let q = query else { icons = []; return }
        generation += 1
        let g = generation, lib = lib
        Task.detached(priority: .userInitiated) {
            let r = lib.icons(q)
            await MainActor.run {
                guard g == self.generation else { return }
                self.icons = r
                self.selection = self.selection.intersection(Set(r.map(\.id)))
            }
        }
    }

    private func debounceReload() {
        debounce?.cancel()
        debounce = Task { try? await Task.sleep(nanoseconds: 180_000_000); if !Task.isCancelled { reload() } }
    }

    var selectedIcons: [Icon] { icons.filter { selection.contains($0.id) } }

    var title: String {
        switch item {
        case .all: return L("side.all")
        case .starred: return L("side.starred")
        case .recent: return L("side.recent")
        case .micone: return "MiCONE"
        case .group(let id): return groups.first { $0.id == id }?.name ?? ""
        case .collection(let id): return collections.first { $0.id == id }?.name ?? ""
        case .portal(let id): return portals.first { $0.id == id }?.name ?? ""
        }
    }

    func say(_ text: String, error: Bool = false) {
        let t = Toast(text: text, error: error)
        toast = t
        Task { try? await Task.sleep(nanoseconds: 3_500_000_000); if self.toast?.id == t.id { self.toast = nil } }
    }

    // MARK: Sélection

    func click(_ icon: Icon, command: Bool, shift: Bool) {
        if shift, let a = anchor, let i = icons.firstIndex(where: { $0.id == a }), let j = icons.firstIndex(where: { $0.id == icon.id }) {
            selection = Set(icons[min(i, j)...max(i, j)].map(\.id))
        } else if command {
            if selection.contains(icon.id) { selection.remove(icon.id) } else { selection.insert(icon.id) }
            anchor = icon.id
        } else { selection = [icon.id]; anchor = icon.id }
    }

    // MARK: Actions sur les icônes

    func toggleStar(_ list: [Icon]) {
        let on = !list.allSatisfy(\.starred)
        lib.setStarred(list.map(\.id), on)
        reload()
    }

    func copy(_ icon: Icon) { IconExport.copy(icon, lib: lib); say(L("toast.copied", icon.name)) }

    func delete(_ list: [Icon]) {
        lib.delete(list.map(\.id)); selection = []; reload()
        say(L("toast.deleted", list.count))
    }

    func move(_ list: [Icon], to collection: String) {
        for i in list { lib.update(i.id, collection: collection) }
        reload()
    }

    func rename(_ icon: Icon, name: String, tags: String) {
        if name != icon.name { lib.update(icon.id, name: name) }
        if tags != icon.tags { lib.update(icon.id, tags: tags) }
        reload()
    }

    func reveal(_ list: [Icon]) { NSWorkspace.shared.activateFileViewerSelecting(list.map { lib.fileURL($0) }) }

    func exportPNG(_ list: [Icon], side: Int) {
        guard !list.isEmpty else { return }
        let dest: URL
        if list.count == 1 {
            let p = NSSavePanel(); p.allowedContentTypes = [.png]; p.nameFieldStringValue = "\(list[0].name).png"
            guard p.runModal() == .OK, let u = p.url else { return }
            dest = u
            if let d = IconExport.png(list[0], lib: lib, side: side) { try? d.write(to: dest); say(L("toast.exported", 1)) }
            return
        }
        guard let dir = pickFolder(L("export.choose")) else { return }
        var n = 0
        for i in list { if let d = IconExport.png(i, lib: lib, side: side) { try? d.write(to: dir.appendingPathComponent("\(Library.safeName(i.name)).png")); n += 1 } }
        say(L("toast.exported", n))
    }

    func exportOriginals(_ list: [Icon]) {
        guard let dir = pickFolder(L("export.choose")) else { return }
        var n = 0
        for i in list {
            let to = dir.appendingPathComponent(i.file)
            try? FileManager.default.removeItem(at: to)
            if (try? FileManager.default.copyItem(at: lib.fileURL(i), to: to)) != nil { n += 1 }
        }
        say(L("toast.exported", n))
    }

    func pickFolder(_ message: String) -> URL? {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true; p.message = message
        return p.runModal() == .OK ? p.url : nil
    }

    // MARK: Groupes et collections

    func newCollection(name: String, group: String? = nil) {
        if let c = try? lib.addCollection(name: name, group: group) { refreshSidebar(); item = .collection(c.id) }
    }

    func newGroup(name: String, parent: String? = nil) {
        if let g = try? lib.addGroup(name: name, parent: parent) { expanded.insert(g.id); if let parent { expanded.insert(parent) }; refreshSidebar() }
    }

    func deleteSidebar(_ it: SidebarItem) {
        switch it {
        case .collection(let id): lib.deleteCollection(id)
        case .group(let id): lib.deleteGroup(id)
        case .portal(let id): lib.deletePortal(id)
        default: return
        }
        if item == it { item = .all }
        refreshSidebar(); reload()
    }

    func rename(_ it: SidebarItem, to name: String) {
        switch it {
        case .collection(let id): lib.renameCollection(id, to: name)
        case .group(let id): lib.renameGroup(id, to: name)
        default: return
        }
        refreshSidebar()
    }

    // MARK: Import

    func chooseImport(_ kind: ImportKind) {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = kind == .files
        switch kind {
        case .iconjar: p.message = L("import.iconjar.message"); p.canChooseDirectories = true
        case .folder: p.message = L("import.folder.message"); p.canChooseFiles = false
        case .files: p.message = L("import.files.message"); p.canChooseDirectories = false
        }
        guard p.runModal() == .OK else { return }
        importURLs(p.urls)
    }

    enum ImportKind { case iconjar, folder, files }

    /// Importe ce qui est déposé ou ouvert : bibliothèque IconJar, dossier, fichiers.
    func importURLs(_ urls: [URL]) {
        let lib = lib
        var files: [URL] = []
        for u in urls {
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let title = IconJarImporter.isLibrary(u) ? L("import.iconjar.title", u.deletingPathExtension().lastPathComponent) : L("import.folder.title", u.lastPathComponent)
                run(title) { prog in
                    if IconJarImporter.isLibrary(u) { return try IconJarImporter.importLibrary(at: u, into: lib, progress: prog) }
                    return try FolderImporter.importFolder(at: u, into: lib, groupNamed: nil, progress: prog)
                }
            } else if ImageMeta.supported.contains(u.pathExtension.lowercased()) { files.append(u) }
        }
        guard !files.isEmpty else { return }
        let coll: String
        if case .collection(let id) = item { coll = id }
        else if let c = try? lib.collection(named: L("import.loose"), kind: .normal) { coll = c.id } else { return }
        let r = FolderImporter.importFiles(files, into: coll, lib: lib)
        reload(); say(L("toast.imported", r.icons))
    }

    private func run(_ title: String, _ work: @escaping @Sendable (@escaping ProgressHandler) throws -> ImportReport) {
        progress = ImportProgress(title: title, fraction: 0, detail: "")
        Task.detached(priority: .utility) {
            do {
                let r = try work { f, d in Task { @MainActor in self.progress?.fraction = f; self.progress?.detail = d } }
                await MainActor.run {
                    self.progress = nil; self.reload()
                    self.say(L("toast.imported.detail", r.icons, r.collections) + (r.missing > 0 ? " " + L("toast.imported.missing", r.missing) : ""))
                }
            } catch {
                await MainActor.run { self.progress = nil; self.say(L("toast.import.failed", error.localizedDescription), error: true) }
            }
        }
    }

    /// Un navigateur par portail, conservé tant que l'appli tourne : on retrouve la page en revenant sur le portail.
    func controller(for portal: Portal) -> PortalController {
        if let c = controllers[portal.id], c.portal == portal { return c }
        let c = PortalController(portal: portal, model: self)
        controllers[portal.id] = c
        return c
    }

    // MARK: Lien MiCONE

    func startInbox() {
        processInbox()
        let fd = open(lib.inboxDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            // laisse MiCONE finir d'écrire le fichier et son descripteur
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self?.processInbox() } }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        inboxSource = src
    }

    func processInbox() {
        let lib = lib
        Task.detached {
            let ids = Inbox.process(lib)
            guard !ids.isEmpty else { return }
            Thumbs.shared.forget()
            await MainActor.run {
                self.reload()
                self.say(L("toast.micone", ids.count))
            }
        }
    }
}

extension Library {
    static func safeName(_ s: String) -> String { fileSafe(s) }
}
