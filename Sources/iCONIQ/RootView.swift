import SwiftUI
import UniformTypeIdentifiers
import iCONIQCore

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model).frame(width: 250)
            Rectangle().fill(Socle.C.border).frame(width: 1)
            Group {
                if case .portal(let id) = model.item, let p = model.portals.first(where: { $0.id == id }) {
                    PortalView(model: model, portal: p).id(p.id)
                } else {
                    LibraryView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Socle.C.bg)
        .overlay(alignment: .bottom) { if let t = model.toast { ToastView(toast: t).padding(.bottom, Socle.M.space6).transition(.move(edge: .bottom).combined(with: .opacity)) } }
        .overlay { if let p = model.progress { ProgressCard(progress: p) } }
        .overlay { if dropTargeted { DropOverlay() } }
        .animation(.easeOut(duration: 0.18), value: model.toast)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(targeted: $dropTargeted) { urls in model.importURLs(urls) })
        .sheet(item: $model.portalSheet) { PortalSheet(model: model, portal: $0) }
        .frame(minWidth: WindowConfigurator.minSize.width, minHeight: WindowConfigurator.minSize.height)
        .background(WindowConfigurator())
    }
}

/// Marqueur des glissers internes (icônes d'iCONIQ) : le fichier qu'ils portent pour le Finder ne doit pas être importé.
enum IconDrag {
    static let type = UTType(exportedAs: "fr.stephan.iconiq.icons")
}

/// Dépôt de fichiers venus de l'extérieur (Finder…) : importés. Les glissers internes sont refusés ici.
struct FileDropDelegate: DropDelegate {
    @Binding var targeted: Bool
    let onFiles: ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) && !info.hasItemsConforming(to: [IconDrag.type]) }
    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }
    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        let providers = info.itemProviders(for: [.fileURL])
        Task {
            var urls: [URL] = []
            for p in providers {
                if let d = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { urls.append(u) }
            }
            await MainActor.run { onFiles(urls) }
        }
        return true
    }
}

struct ProgressCard: View {
    let progress: ImportProgress
    var body: some View {
        ZStack {
            Socle.C.scrim
            VStack(alignment: .leading, spacing: Socle.M.space3) {
                Text(progress.title).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                ProgressBar(fraction: progress.fraction)
                HStack {
                    Text(progress.detail).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
                    Spacer()
                    Text("\(Int(progress.fraction * 100)) %").socle(Socle.T.meta).foregroundStyle(Socle.C.accentText)
                }
            }
            .padding(Socle.M.space6).frame(width: 440)
            .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(Socle.C.border, lineWidth: 1))
        }
    }
}

struct DropOverlay: View {
    var body: some View {
        ZStack {
            Socle.C.scrim
            VStack(spacing: Socle.M.space3) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 34)).foregroundStyle(Socle.C.accent)
                Text(L("drop.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                Text(L("drop.sub")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
            }
            .padding(Socle.M.space8)
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(Socle.C.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        }.allowsHitTesting(false)
    }
}

// MARK: - Barre latérale

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @State private var renaming: SidebarItem?
    @State private var renameText = ""
    @State private var creating: (kind: String, parent: String?)?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Socle.M.space2) {
                IconiqMark().foregroundStyle(Brand.color).frame(width: 22, height: 22)
                Text(branded: "iCONIQ").socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                Spacer()
            }
            .padding(.horizontal, Socle.M.space4).frame(height: Socle.M.sizeBar + 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    row(.all, "square.grid.2x2", L("side.all"), model.total)
                    row(.starred, "star", L("side.starred"), nil)
                    row(.recent, "clock", L("side.recent"), nil)

                    header(L("side.library")) {
                        Menu {
                            Button(L("side.newCollection")) { creating = ("collection", nil); newName = "" }
                            Button(L("side.newGroup")) { creating = ("group", nil); newName = "" }
                        } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                    }
                    tree(parent: nil, level: 0)

                    header(L("side.portals")) {
                        Button { model.portalSheet = Portal(id: UUID().uuidString, name: "", url: "", searchURL: "", sort: model.portals.count) } label: {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        }.buttonStyle(.plain).help(L("portal.add"))
                    }
                    ForEach(model.portals) { p in
                        row(.portal(p.id), "globe", p.name, nil)
                            .contextMenu {
                                Button(L("portal.edit")) { model.portalSheet = p }
                                Button(L("common.delete"), role: .destructive) { model.deleteSidebar(.portal(p.id)) }
                            }
                    }
                    if model.portals.isEmpty { Hint(L("portal.none")).padding(.horizontal, Socle.M.space4).padding(.top, 4) }
                }
                .padding(.horizontal, Socle.M.space2).padding(.bottom, Socle.M.space4)
            }
        }
        .background(Socle.C.surfaceRaised)
        .alert(creating?.kind == "group" ? L("side.newGroup") : L("side.newCollection"), isPresented: Binding(get: { creating != nil }, set: { if !$0 { creating = nil } })) {
            TextField(L("common.name"), text: $newName)
            Button(L("common.create")) {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty, let c = creating { c.kind == "group" ? model.newGroup(name: n, parent: c.parent) : model.newCollection(name: n, group: c.parent) }
                creating = nil
            }
            Button(L("common.cancel"), role: .cancel) { creating = nil }
        }
        .alert(L("common.rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("common.name"), text: $renameText)
            Button(L("common.rename.ok")) { if let r = renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty { model.rename(r, to: renameText) }; renaming = nil }
            Button(L("common.cancel"), role: .cancel) { renaming = nil }
        }
    }

    private func header(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(title.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textSubtle)
            Spacer()
            trailing().foregroundStyle(Socle.C.textMuted)
        }
        .padding(.horizontal, Socle.M.space2_5).padding(.top, Socle.M.space5).padding(.bottom, 4)
    }

    private func tree(parent: String?, level: Int) -> AnyView {
        AnyView(Group {
            ForEach(model.groups.filter { $0.parent == parent }) { g in
                let open = model.expanded.contains(g.id)
                row(.group(g.id), open ? "folder.fill" : "folder", g.name, nil, level: level, chevron: open)
                    .contextMenu {
                        Button(L("side.newCollection")) { creating = ("collection", g.id); newName = "" }
                        Button(L("side.newGroup")) { creating = ("group", g.id); newName = "" }
                        Button(L("common.rename")) { renaming = .group(g.id); renameText = g.name }
                        Divider()
                        Button(L("common.delete"), role: .destructive) { model.deleteSidebar(.group(g.id)) }
                    }
                if open { tree(parent: g.id, level: level + 1) }
            }
            ForEach(model.collections.filter { $0.group == parent && $0.kind != .micone }) { c in
                row(.collection(c.id), c.kind == .portal ? "globe" : "photo.on.rectangle", c.name, c.count, level: level)
                    .modifier(CollectionDrop(model: model, collection: c))
                    .contextMenu {
                        Button(L("common.rename")) { renaming = .collection(c.id); renameText = c.name }
                        Menu(L("side.moveTo")) {
                            Button(L("side.root")) { model.lib.moveCollection(c.id, to: nil); model.refreshSidebar() }
                            ForEach(model.groups) { g in Button(g.name) { model.lib.moveCollection(c.id, to: g.id); model.refreshSidebar() } }
                        }
                        Divider()
                        Button(L("common.delete"), role: .destructive) { model.deleteSidebar(.collection(c.id)) }
                    }
            }
        })
    }

    private func row(_ item: SidebarItem, _ symbol: String, _ title: String, _ count: Int?, level: Int = 0, chevron: Bool? = nil) -> some View {
        SideRow(symbol: symbol, title: title, count: count, level: level, chevron: chevron, selected: model.item == item) {
            if case .group(let id) = item {
                if model.expanded.contains(id) { model.expanded.remove(id) } else { model.expanded.insert(id) }
            }
            model.item = item
        }
    }
}

/// Une collection de la barre latérale reçoit les icônes glissées depuis la grille.
struct CollectionDrop: ViewModifier {
    let model: AppModel
    let collection: IconCollection
    @State private var over = false
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(Socle.C.accent, lineWidth: over ? 2 : 0).allowsHitTesting(false))
            .onDrop(of: [IconDrag.type], delegate: Target(model: model, collection: collection, over: $over))
    }
    struct Target: DropDelegate {
        let model: AppModel
        let collection: IconCollection
        @Binding var over: Bool
        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [IconDrag.type]) }
        func dropEntered(info: DropInfo) { over = true }
        func dropExited(info: DropInfo) { over = false }
        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
        func performDrop(info: DropInfo) -> Bool { over = false; model.moveDragged(to: collection); return true }
    }
}

struct SideRow: View {
    let symbol: String, title: String
    let count: Int?
    let level: Int
    let chevron: Bool?
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: Socle.M.space2) {
                if let chevron { Image(systemName: chevron ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Socle.C.textSubtle).frame(width: 8) }
                Image(systemName: symbol).font(.system(size: 12)).frame(width: 16).foregroundStyle(selected ? Socle.C.accentText : Socle.C.textMuted)
                Text(title).socle(Socle.T.body).foregroundStyle(selected ? Socle.C.textStrong : Socle.C.text).lineLimit(1)
                Spacer(minLength: 4)
                if let count { Text("\(count)").socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle) }
            }
            .padding(.leading, Socle.M.space2_5 + CGFloat(level) * 14).padding(.trailing, Socle.M.space2_5)
            .frame(height: 30)
            .background(selected ? Socle.C.surfaceSelected : (hover ? Socle.C.surfaceHover : .clear), in: RoundedRectangle(cornerRadius: Socle.M.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}
