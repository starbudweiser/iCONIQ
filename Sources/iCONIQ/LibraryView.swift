import SwiftUI
import iCONIQCore

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @AppStorage("tileSize") private var tile = 112.0
    @AppStorage("previewBG") private var bg = PreviewBG.checker.rawValue
    @State private var cellFrames: [String: CGRect] = [:]
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            bar
            Rectangle().fill(Socle.C.border).frame(height: 1)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    content
                    Rectangle().fill(Socle.C.border).frame(height: 1)
                    statusBar
                }
                if model.inspectorOpen {
                    Rectangle().fill(Socle.C.border).frame(width: 1)
                    InspectorView(model: model).frame(width: 340)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bar: some View {
        HStack(spacing: Socle.M.space3) {
            Text(model.title).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).lineLimit(1)
            Spacer(minLength: Socle.M.space3)
            SearchField(prompt: L("lib.search"), text: $model.search).frame(width: 300)
            BarButton(symbol: "sidebar.right", help: L("lib.inspector"), active: model.inspectorOpen) { model.inspectorOpen.toggle() }
            ImportMenu(model: model)
        }
        .padding(.horizontal, Socle.M.space4).frame(height: Socle.M.sizeBar + 8)
        .background(Socle.C.surfaceRaised)
    }

    /// Barre d'état : nombre d'icônes à gauche ; fond d'aperçu, tri et taille des vignettes à droite.
    private var statusBar: some View {
        HStack(spacing: Socle.M.space3) {
            Text(L("lib.count", model.icons.count) + (model.selection.isEmpty ? "" : " · " + L("lib.selected", model.selection.count)))
                .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
            Spacer()
            Menu {
                Picker(L("lib.bg"), selection: $bg) {
                    ForEach(PreviewBG.allCases, id: \.rawValue) { Label($0.label, systemImage: $0.symbol).tag($0.rawValue) }
                }.pickerStyle(.inline)
            } label: { Image(systemName: PreviewBG(rawValue: bg)?.symbol ?? "checkerboard.rectangle").foregroundStyle(Socle.C.textMuted) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: Socle.M.sizeControl).help(L("lib.bg") + " : " + (PreviewBG(rawValue: bg)?.label ?? ""))
            Menu {
                Picker(L("lib.sort"), selection: $model.sort) {
                    Text(L("lib.sort.name")).tag(IconSort.name)
                    Text(L("lib.sort.added")).tag(IconSort.added)
                    Text(L("lib.sort.size")).tag(IconSort.size)
                }.pickerStyle(.inline)
            } label: { Image(systemName: "arrow.up.arrow.down").foregroundStyle(Socle.C.textMuted) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: Socle.M.sizeControl).help(L("lib.sort"))
            Image(systemName: "square.grid.3x3").font(.system(size: 10)).foregroundStyle(Socle.C.textSubtle)
            Slider(value: $tile, in: 72...200).frame(width: 110).tint(Socle.C.accent).help(L("lib.size"))
            Image(systemName: "square.grid.2x2").font(.system(size: 12)).foregroundStyle(Socle.C.textSubtle)
        }
        .padding(.horizontal, Socle.M.space4).frame(height: Socle.M.sizeControl + 4)
        .background(Socle.C.surfaceRaised)
    }

    @ViewBuilder private var content: some View {
        if model.icons.isEmpty {
            EmptyLibrary(model: model)
        } else {
            GeometryReader { geo in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tile, maximum: tile + 40), spacing: Socle.M.space3)], spacing: Socle.M.space3) {
                        ForEach(model.icons) { icon in
                            IconCell(model: model, icon: icon, selected: model.selection.contains(icon.id), tile: tile, bg: PreviewBG(rawValue: bg) ?? .checker)
                                .background(GeometryReader { g in Color.clear.preference(key: CellFramesKey.self, value: [icon.id: g.frame(in: .named("grid"))]) })
                        }
                    }
                    .padding(Socle.M.space4)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                    .background(marqueeLayer)
                    .overlay(alignment: .topLeading) { marqueeBox }
                    .coordinateSpace(name: "grid")
                    .onPreferenceChange(CellFramesKey.self) { cellFrames = $0 }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Socle.C.bg)
            .focusable().focusEffectDisabled()
            .onDeleteCommand { confirmDelete(model.selectedIcons) }
            .onKeyPress(.escape) { model.selection = []; return .handled }
            .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
                guard press.modifiers == .command else { return .ignored }
                model.selection = Set(model.icons.map(\.id))
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "c"), phases: .down) { press in
                guard press.modifiers == .command, let icon = model.selectedIcons.first else { return .ignored }
                model.copy(icon)
                return .handled
            }
        }
    }

    /// Fond du quadrillage : un glisser démarré dans le vide trace un cadre qui sélectionne les icônes touchées
    /// (⌘ ou ⇧ : ajoute à la sélection existante) ; un simple clic dans le vide désélectionne.
    private var marqueeLayer: some View {
        Color.clear.contentShape(Rectangle())
            .onTapGesture { model.selection = [] }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
                .onChanged { v in
                    if marquee == nil {
                        let f = NSEvent.modifierFlags
                        marqueeBase = (f.contains(.command) || f.contains(.shift)) ? model.selection : []
                    }
                    let r = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                                   width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
                    marquee = r
                    let hit = Set(cellFrames.filter { $0.value.intersects(r) }.keys)
                    let next = marqueeBase.union(hit)
                    if next != model.selection { model.selection = next }
                }
                .onEnded { _ in marquee = nil })
    }

    @ViewBuilder private var marqueeBox: some View {
        if let r = marquee {
            RoundedRectangle(cornerRadius: 2).fill(Socle.C.accent.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Socle.C.accent, lineWidth: 1))
                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                .allowsHitTesting(false)
        }
    }

    private func confirmDelete(_ list: [Icon]) {
        guard !list.isEmpty else { return }
        let a = NSAlert()
        a.messageText = L("delete.confirm", list.count)
        a.informativeText = L("delete.confirm.info")
        a.addButton(withTitle: L("common.delete")); a.addButton(withTitle: L("common.cancel"))
        if a.runModal() == .alertFirstButtonReturn { model.delete(list) }
    }
}

private struct CellFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct ImportMenu: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Menu {
            Button(L("import.iconjar")) { model.chooseImport(.iconjar) }
            Button(L("import.folder")) { model.chooseImport(.folder) }
            Button(L("import.files")) { model.chooseImport(.files) }
        } label: {
            Text(L("import.button")).socle(Socle.T.button).foregroundStyle(Socle.C.onAction)
                .padding(.horizontal, Socle.M.space4).frame(height: Socle.M.sizeControl)
                .background(Socle.C.action, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

struct EmptyLibrary: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: Socle.M.space4) {
            IconiqMark().foregroundStyle(Socle.C.borderStrong).frame(width: 90, height: 90)
            if model.search.isEmpty && model.total == 0 {
                Text(L("empty.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                Text(branded: L("empty.body")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).multilineTextAlignment(.center).frame(maxWidth: 420)
                ImportMenu(model: model)
            } else {
                Text(model.search.isEmpty ? L("empty.collection") : L("empty.search")).socle(Socle.T.title).foregroundStyle(Socle.C.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Socle.C.bg)
    }
}

struct IconCell: View {
    @ObservedObject var model: AppModel
    let icon: Icon
    let selected: Bool
    let tile: Double
    let bg: PreviewBG
    @State private var image: NSImage?
    @State private var lastTap = Date.distantPast

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                PreviewBackground(mode: bg).clipShape(RoundedRectangle(cornerRadius: Socle.M.radiusMd))
                if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(tile * 0.17) }
                else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
                if icon.starred { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Socle.C.action).padding(5) }
            }
            .frame(height: tile)
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(selected ? Socle.C.accent : Socle.C.border.opacity(bg == .dark ? 1 : 0), lineWidth: selected ? 2 : 1))
            Text(icon.name).socle(Socle.T.caption).foregroundStyle(selected ? Socle.C.textStrong : Socle.C.textMuted).lineLimit(1)
        }
        .padding(4)
        .background(selected ? Socle.C.surfaceSelected : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
        .contentShape(Rectangle())
        .task(id: "\(icon.file)-\(tile > 110)") {
            image = await Thumbs.shared.image(for: icon, lib: model.lib, side: tile > 110 ? 256 : 128)
        }
        // Un seul geste : deux onTapGesture (count 2 puis 1) font attendre le délai du double-clic avant de sélectionner.
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastTap) < NSEvent.doubleClickInterval { lastTap = .distantPast; model.selection = [icon.id]; model.copy(icon); return }
            lastTap = now
            let f = NSEvent.modifierFlags
            model.click(icon, command: f.contains(.command), shift: f.contains(.shift))
        }
        .onDrag {
            // Glisser vers une collection de la barre latérale (déplacement) ou vers le Finder (le fichier). Une icône
            // hors sélection devient la sélection ; sinon c'est toute la sélection qui part.
            if !model.selection.contains(icon.id) { model.selection = [icon.id] }
            model.dragIDs = Array(model.selection)
            let provider = NSItemProvider(contentsOf: model.lib.fileURL(icon)) ?? NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: IconDrag.type.identifier, visibility: .ownProcess) { done in
                done(Data(model.dragIDs.joined(separator: "\n").utf8), nil); return nil
            }
            return provider
        }
        .contextMenu { IconMenu(model: model, icon: icon) }
    }
}

struct IconMenu: View {
    @ObservedObject var model: AppModel
    let icon: Icon
    private var targets: [Icon] { model.selection.contains(icon.id) ? model.selectedIcons : [icon] }
    var body: some View {
        Button(L("act.copy")) { model.copy(icon) }
        if icon.fmt == "svg" { Button(L("act.copySVG")) { IconExport.copySVGCode(icon, lib: model.lib); model.say(L("toast.copiedCode")) } }
        Button(targets.allSatisfy(\.starred) ? L("act.unstar") : L("act.star")) { model.toggleStar(targets) }
        Divider()
        Menu(L("act.exportPNG")) { ForEach([64, 128, 256, 512, 1024], id: \.self) { s in Button("\(s) px") { model.exportPNG(targets, side: s) } } }
        Button(L("act.exportOriginals")) { model.exportOriginals(targets) }
        Button(L("act.reveal")) { model.reveal(targets) }
        if targets.count == 1 { Button(L("act.rename")) { model.promptRename(icon) } }
        Menu(L("side.moveTo")) { ForEach(model.collections.filter { $0.kind != .micone || true }) { c in Button(c.name) { model.move(targets, to: c.id) } } }
        Divider()
        Button(L("common.delete"), role: .destructive) { model.delete(targets) }
    }
}

// MARK: - Inspecteur

struct InspectorView: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var tags = ""
    @State private var preview: NSImage?
    @AppStorage("previewBG") private var bg = PreviewBG.checker.rawValue

    private var single: Icon? { model.selectedIcons.count == 1 ? model.selectedIcons[0] : nil }

    var body: some View {
        Group {
            if let icon = single { detail(icon) }
            else if model.selection.count > 1 { multi }
            else { VStack { Spacer(); Text(L("insp.none")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle); Spacer() }.frame(maxWidth: .infinity) }
        }
        .background(Socle.C.surfaceRaised)
    }

    private func detail(_ icon: Icon) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
                ZStack {
                    PreviewBackground(mode: PreviewBG(rawValue: bg) ?? .checker, cell: 12).clipShape(RoundedRectangle(cornerRadius: Socle.M.radiusMd))
                    if let preview { Image(nsImage: preview).resizable().interpolation(.high).scaledToFit().padding(28) }
                }
                .frame(height: 230)
                .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))

                field(L("insp.name")) { TextField("", text: $name).socleField().onSubmit { commit(icon) } }
                field(L("insp.tags")) {
                    TextField(L("insp.tags.hint"), text: $tags).socleField().onSubmit { commit(icon) }
                    FlowChips(tags: icon.tagList)
                }

                VStack(alignment: .leading, spacing: 6) {
                    info(L("insp.format"), icon.fmt.uppercased() + (icon.width > 0 ? " · \(icon.width)×\(icon.height)" : ""))
                    info(L("insp.collection"), model.collections.first { $0.id == icon.collection }?.name ?? "")
                    info(L("insp.added"), icon.added.formatted(date: .abbreviated, time: .omitted))
                    if !icon.sourceURL.isEmpty { link(L("insp.source"), icon.sourceURL) }
                    if !icon.linkPath.isEmpty { info(L("insp.linked"), icon.linkPath) }
                }

                VStack(spacing: Socle.M.space3) {
                    Button(L("act.copy")) { model.copy(icon) }.buttonStyle(SocleButtonStyle(.primary)).lineLimit(1)
                    HStack(spacing: Socle.M.space1) {
                        BarButton(symbol: icon.starred ? "star.fill" : "star", help: icon.starred ? L("act.unstar") : L("act.star"), active: icon.starred) { model.toggleStar([icon]) }
                        Menu { ForEach([64, 128, 256, 512, 1024], id: \.self) { s in Button("\(s) px") { model.exportPNG([icon], side: s) } } } label: {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(Socle.C.textMuted).frame(width: Socle.M.sizeControl, height: Socle.M.sizeControl)
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: Socle.M.sizeControl).help(L("act.exportPNG"))
                        BarButton(symbol: "chevron.left.forwardslash.chevron.right", help: L("act.copySVG")) { IconExport.copySVGCode(icon, lib: model.lib); model.say(L("toast.copiedCode")) }
                            .disabled(icon.fmt != "svg")
                        BarButton(symbol: "folder", help: L("act.reveal")) { model.reveal([icon]) }
                        Spacer()
                        BarButton(symbol: "trash", help: L("common.delete")) { model.delete([icon]) }
                    }
                }
            }
            .padding(Socle.M.space4)
        }
        .onAppear { sync(icon) }
        .onChange(of: icon.id) { _, _ in sync(icon) }
        .onChange(of: icon.file) { _, _ in sync(icon) }
        .task(id: icon.id + icon.file) { preview = await Thumbs.shared.image(for: icon, lib: model.lib, side: 512) }
    }

    private var multi: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            Text(L("insp.multi", model.selection.count)).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
            Button(model.selectedIcons.allSatisfy(\.starred) ? L("act.unstar") : L("act.star")) { model.toggleStar(model.selectedIcons) }.buttonStyle(SocleButtonStyle(.secondary))
            Menu(L("act.exportPNG")) { ForEach([64, 128, 256, 512, 1024], id: \.self) { s in Button("\(s) px") { model.exportPNG(model.selectedIcons, side: s) } } }
                .menuStyle(.button).buttonStyle(SocleButtonStyle(.secondary)).menuIndicator(.hidden)
            Button(L("act.exportOriginals")) { model.exportOriginals(model.selectedIcons) }.buttonStyle(SocleButtonStyle(.secondary))
            Menu(L("side.moveTo")) { ForEach(model.collections) { c in Button(c.name) { model.move(model.selectedIcons, to: c.id) } } }
                .menuStyle(.button).buttonStyle(SocleButtonStyle(.secondary)).menuIndicator(.hidden)
            Button(L("common.delete")) { model.delete(model.selectedIcons) }.buttonStyle(SocleButtonStyle(.secondary))
            Spacer()
        }
        .padding(Socle.M.space4)
    }

    private func sync(_ icon: Icon) { name = icon.name; tags = icon.tags }
    private func commit(_ icon: Icon) { model.rename(icon, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? icon.name : name, tags: tags) }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted)
            content()
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).frame(width: 78, alignment: .leading)
            Text(v).socle(Socle.T.meta).foregroundStyle(Socle.C.text).lineLimit(2).truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func link(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).frame(width: 78, alignment: .leading)
            Button { if let u = URL(string: v) { NSWorkspace.shared.open(u) } } label: {
                Text(v).socle(Socle.T.meta).foregroundStyle(Socle.C.accentText).lineLimit(1).truncationMode(.middle)
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }
}

struct FlowChips: View {
    let tags: [String]
    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) { ForEach(tags.prefix(6), id: \.self) { SocleChip(text: $0) } }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
