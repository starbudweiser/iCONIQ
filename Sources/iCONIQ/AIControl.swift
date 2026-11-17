import AppKit
import SwiftUI
import iCONIQCore

/// État du pilotage par IA vu par l'appli : réglages partagés avec l'auxiliaire `iconiq-mcp`, clients, journal.
@MainActor
final class MCPModel: ObservableObject {
    static let shared = MCPModel()
    @Published private(set) var settings = MCPStore.load()
    @Published private(set) var connectors: [MCPClientInfo] = []
    @Published private(set) var log: [String] = []
    @Published var message: String?
    private var observers: [NSObjectProtocol] = []

    var helperPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/iconiq-mcp").path }
    var pending: [String] { settings.clients.filter { $0.value == .pending }.map(\.key).sorted() }

    private init() {
        refresh()
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: MCPStore.settingsChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MCPModel.shared.refresh() }
        })
        observers.append(center.addObserver(forName: MCPStore.libraryChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.reload(); MCPModel.shared.refresh() }
        })
    }

    func refresh() {
        settings = MCPStore.load()
        connectors = Connectors.list()
        log = MCPStore.readLog(last: 40).reversed()
    }

    func change(_ edit: @escaping (inout MCPSettings) -> Void) { settings = MCPStore.update(Library.defaultRoot, edit) }

    func setClient(_ name: String, _ state: MCPSettings.ClientState?) { change { $0.clients[name] = state } }

    func connect(_ id: String) {
        do { try Connectors.connect(id: id, helper: helperPath); message = L("mcp.connected") }
        catch { message = L("mcp.connect.failed", error.localizedDescription) }
        refresh()
    }

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Connectors.command(helper: helperPath), forType: .string)
        message = L("mcp.copied")
    }
}

// MARK: Onglet Pilotage IA

struct AIControlView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var mcp = MCPModel.shared

    var body: some View {
        ScrollView {
            if mcp.settings.enabled {
                SocleModuleGrid(minimum: 400) {
                    authorization
                    clients
                    filing
                    making
                    protection
                    journal
                }
                .padding(Socle.M.space6)
            } else {
                welcome.padding(Socle.M.space6)
            }
        }
        .background(Socle.C.bg)
        .onAppear { mcp.refresh() }
    }

    // État désactivé : une seule carte centrée, un seul appel principal.
    private var welcome: some View {
        VStack(spacing: Socle.M.space4) {
            HStack(spacing: Socle.M.space4) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                Image(systemName: "arrow.right").foregroundStyle(Socle.C.textSubtle)
                FolderGlyph(color: Color(hex: "#56acf0")).frame(width: 60, height: 60)
            }
            Text(L("mcp.welcome.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).multilineTextAlignment(.center)
            Text(branded: L("mcp.welcome.text")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 520)
            Button(L("mcp.enable")) { mcp.change { $0.enabled = true } }.buttonStyle(SocleButtonStyle(.action)).fixedSize()
            Hint(L("mcp.welcome.after"))
        }
        .padding(Socle.M.space6)
        .frame(maxWidth: 720)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(Socle.C.border, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    private var authorization: some View {
        Card(title: L("mcp.auth.title")) {
            Check(title: L("mcp.enable"), help: L("mcp.enable.help"), isOn: Binding(get: { mcp.settings.enabled }, set: { v in mcp.change { $0.enabled = v } }))
            Text(branded: L("mcp.auth.note")).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Socle.M.space2).padding(.horizontal, Socle.M.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Socle.C.surfaceRaised)
                .overlay(alignment: .leading) { Rectangle().fill(Socle.C.infoBorder).frame(width: 2) }
        }
    }

    private var clients: some View {
        Card(title: L("mcp.clients.title")) {
            Hint(L("mcp.clients.help"))
            let known = Set(mcp.connectors.map(\.id))
            ForEach(mcp.connectors) { c in
                ClientRow(name: c.name, detail: detail(c), state: mcp.settings.clients[c.id]) {
                    if c.status != .connected { Button(L("mcp.connect")) { mcp.connect(c.id) }.buttonStyle(SocleButtonStyle(.primary)).fixedSize().disabled(c.status == .notDetected) }
                } actions: { stateButtons(c.id) }
            }
            ForEach(mcp.settings.clients.keys.sorted().filter { !known.contains($0) }, id: \.self) { name in
                ClientRow(name: name, detail: stateText(mcp.settings.clients[name]), state: mcp.settings.clients[name]) { EmptyView() } actions: { stateButtons(name) }
            }
            HStack(spacing: Socle.M.space2) {
                Button(L("mcp.copy")) { mcp.copyCommand() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
            }.frame(maxWidth: .infinity)
            if let m = mcp.message { Hint(m) }
        }
    }

    private func detail(_ c: MCPClientInfo) -> String {
        switch c.status {
        case .notDetected: return L("mcp.client.absent")
        case .detected: return L("mcp.client.detected")
        case .connected: return mcp.settings.clients[c.id].map(stateText) ?? L("mcp.client.connected")
        }
    }

    private func stateText(_ s: MCPSettings.ClientState?) -> String {
        switch s {
        case .allowed: return L("mcp.state.allowed")
        case .pending: return L("mcp.state.pending")
        case .denied: return L("mcp.state.denied")
        case nil: return L("mcp.client.connected")
        }
    }

    @ViewBuilder private func stateButtons(_ name: String) -> some View {
        switch mcp.settings.clients[name] {
        case .pending:
            Button(L("mcp.deny")) { mcp.setClient(name, .denied) }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
            Button(L("mcp.allow")) { mcp.setClient(name, .allowed) }.buttonStyle(SocleButtonStyle(.primary)).fixedSize()
        case .allowed, .denied:
            Button(L("mcp.remove")) { mcp.setClient(name, nil) }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
        case nil: EmptyView()
        }
    }

    private var collections: [IconCollection] { model.collections.filter { $0.kind != .portal } }

    private func collectionPicker(_ value: String?, _ set: @escaping (String?) -> Void) -> some View {
        Picker("", selection: Binding(get: { value ?? "" }, set: { set($0.isEmpty ? nil : $0) })) {
            Text(L("mcp.none")).tag("")
            ForEach(collections) { Text($0.name).tag($0.id) }
        }
        .labelsHidden().pickerStyle(.menu).frame(width: 220)
    }

    private var filing: some View {
        Card(title: L("mcp.filing.title")) {
            Hint(L("mcp.filing.help"))
            Row(label: L("mcp.filing.app")) { collectionPicker(mcp.settings.appCollection) { v in mcp.change { $0.appCollection = v } } }
            Row(label: L("mcp.filing.folder")) { collectionPicker(mcp.settings.folderCollection) { v in mcp.change { $0.folderCollection = v } } }
            Text(L("mcp.rules")).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).padding(.top, Socle.M.space2)
            ForEach(mcp.settings.rules) { rule in RuleRow(rule: rule, collections: collections) }
            Button(L("mcp.rules.add")) { mcp.change { $0.rules.append(MCPSettings.Rule()) } }
                .buttonStyle(SocleButtonStyle(.secondary)).fixedSize().frame(maxWidth: .infinity)
        }
    }

    private static let colors: [(key: String, hex: String, label: String)] = [
        ("bleu", "#56acf0", "mcp.color.blue"), ("nuit", "#2f4f84", "mcp.color.night"), ("graphite", "#8c8c94", "mcp.color.graphite"), ("clair", "#e6e6ec", "mcp.color.light"),
    ]

    private var making: some View {
        Card(title: L("mcp.make.title")) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("mcp.make.color")).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                Hint(L("mcp.make.color.help"))
            }
            HStack(spacing: Socle.M.space2) {
                ForEach(Self.colors, id: \.key) { c in
                    Swatch(color: Color(hex: c.hex), label: L(c.label), on: mcp.settings.folderColor == c.key) { mcp.change { $0.folderColor = c.key } }
                }
                let custom = mcp.settings.folderColor.hasPrefix("#")
                VStack(spacing: 4) {
                    ColorPicker("", selection: Binding(get: { Color(hex: custom ? mcp.settings.folderColor : "#5d5d64") },
                                                       set: { col in mcp.change { $0.folderColor = col.hexString } }), supportsOpacity: false)
                        .labelsHidden().frame(width: 40, height: 40)
                    Text(L("mcp.color.other")).socle(Socle.T.meta).foregroundStyle(custom ? Socle.C.textStrong : Socle.C.textMuted)
                }
                .frame(width: 66).padding(.vertical, Socle.M.space2)
                .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(custom ? Socle.C.accent : .clear, lineWidth: 2))
            }
            Check(title: L("mcp.make.engraved"), help: L("mcp.make.engraved.help"), isOn: Binding(get: { mcp.settings.engraved }, set: { v in mcp.change { $0.engraved = v } }))
            Check(title: L("mcp.make.removebg"), isOn: Binding(get: { mcp.settings.removeBackground }, set: { v in mcp.change { $0.removeBackground = v } }))
        }
    }

    private var protection: some View {
        Card(title: L("mcp.protect.title")) {
            Check(title: L("mcp.protect.backup"), help: L("mcp.protect.backup.help"), isOn: Binding(get: { mcp.settings.backupIcons }, set: { v in mcp.change { $0.backupIcons = v } }))
            Text(L("mcp.protect.refused")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            Button(L("mcp.protect.open")) {
                let dir = MCPStore.backupsDir()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(dir)
            }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize().frame(maxWidth: .infinity)
        }
    }

    private var journal: some View {
        Card(title: L("mcp.log.title")) {
            if mcp.log.isEmpty { Hint(L("mcp.log.empty")) }
            else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(mcp.log.prefix(12).enumerated()), id: \.offset) { _, line in LogLine(line: line) }
                }
                .padding(Socle.M.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Socle.C.bgSunken)
            }
            Button(L("mcp.log.open")) { NSWorkspace.shared.open(MCPStore.logURL()) }
                .buttonStyle(SocleButtonStyle(.secondary)).fixedSize().frame(maxWidth: .infinity).disabled(mcp.log.isEmpty)
        }
    }
}

// MARK: Éléments

private struct Row<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack { Text(label).socle(Socle.T.body).foregroundStyle(Socle.C.text); Spacer(); trailing }
    }
}

private struct ClientRow<Primary: View, Actions: View>: View {
    let name: String
    let detail: String
    let state: MCPSettings.ClientState?
    @ViewBuilder var primary: Primary
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(spacing: Socle.M.space3) {
            Text(String(name.prefix(2)).capitalized).socle(Socle.T.labelStrong).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(Socle.C.controlStrong, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1)
                Text(detail).socle(Socle.T.meta).foregroundStyle(state == .pending ? Socle.C.warning : Socle.C.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Socle.M.space2)
            actions
            primary
        }
        .padding(.vertical, 4)
    }
}

private struct RuleRow: View {
    let rule: MCPSettings.Rule
    let collections: [IconCollection]
    @ObservedObject var mcp = MCPModel.shared
    @State private var text = ""

    private func edit(_ change: @escaping (inout MCPSettings.Rule) -> Void) {
        let id = rule.id
        mcp.change { s in if let i = s.rules.firstIndex(where: { $0.id == id }) { change(&s.rules[i]) } }
    }

    var body: some View {
        HStack(spacing: Socle.M.space2) {
            Picker("", selection: Binding(get: { rule.field }, set: { v in edit { $0.field = v } })) {
                Text(L("mcp.rule.path")).tag("path"); Text(L("mcp.rule.name")).tag("name")
            }.labelsHidden().pickerStyle(.menu).frame(width: 110)
            TextField(L("mcp.rule.contains"), text: $text, onCommit: { let t = text; edit { $0.contains = t } })
                .socleField().frame(minWidth: 90)
                .onAppear { text = rule.contains }
                .onChange(of: text) { _, t in edit { $0.contains = t } }
            Image(systemName: "arrow.right").foregroundStyle(Socle.C.textSubtle)
            Picker("", selection: Binding(get: { rule.collection }, set: { v in edit { $0.collection = v } })) {
                Text(L("mcp.none")).tag("")
                ForEach(collections) { Text($0.name).tag($0.id) }
            }.labelsHidden().pickerStyle(.menu).frame(width: 150)
            Button { let id = rule.id; mcp.change { $0.rules.removeAll { $0.id == id } } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Socle.C.textSubtle).help(L("mcp.rule.delete"))
        }
    }
}

private struct Swatch: View {
    let color: Color
    let label: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                FolderGlyph(color: color).frame(width: 40, height: 40)
                Text(label).socle(Socle.T.meta).foregroundStyle(on ? Socle.C.textStrong : Socle.C.textMuted)
            }
            .frame(width: 66).padding(.vertical, Socle.M.space2)
            .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(on ? Socle.C.accent : .clear, lineWidth: 2))
        }.buttonStyle(.plain)
    }
}

/// Silhouette de dossier (aperçu de couleur), à plat.
struct FolderGlyph: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var back = Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.16, width: w * 0.88, height: h * 0.72), cornerRadius: w * 0.06)
            back.addRoundedRect(in: CGRect(x: w * 0.06, y: h * 0.10, width: w * 0.36, height: h * 0.14), cornerSize: CGSize(width: w * 0.05, height: w * 0.05))
            ctx.fill(back, with: .color(color.opacity(0.7)))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.28, width: w * 0.88, height: h * 0.60), cornerRadius: w * 0.06), with: .color(color))
        }
    }
}

private struct LogLine: View {
    let line: String
    var body: some View {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let time = parts.first.map { String($0.suffix(8)) } ?? ""
        let tool = parts.count > 2 ? parts[2] : ""
        let result = parts.last ?? ""
        let ok = result == "ok"
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(time).socle(Socle.T.monoSm).foregroundStyle(Socle.C.textSubtle)
            Text(tool).socle(Socle.T.monoSm).foregroundStyle(Socle.C.accentText)
            Text(parts.count > 1 ? parts[1] : "").socle(Socle.T.monoSm).foregroundStyle(Socle.C.textMuted).lineLimit(1)
            Spacer(minLength: 4)
            Text(ok ? "✓" : result).socle(Socle.T.monoSm).foregroundStyle(ok ? Socle.C.success : Socle.C.danger).lineLimit(1)
        }
    }
}

/// Bandeau de la fenêtre principale : un client attend l'accord. Ne prend jamais le focus.
struct PendingClientBanner: View {
    @ObservedObject var mcp = MCPModel.shared
    var body: some View {
        if let name = mcp.pending.first {
            HStack(spacing: Socle.M.space3) {
                Image(systemName: "sparkles").foregroundStyle(Socle.C.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text(branded: L("mcp.banner.title", name)).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong)
                    Text(L("mcp.banner.text")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                }
                Spacer()
                Button(L("mcp.deny")) { mcp.setClient(name, .denied) }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Button(L("mcp.allow")) { mcp.setClient(name, .allowed) }.buttonStyle(SocleButtonStyle(.primary)).fixedSize()
            }
            .padding(.vertical, Socle.M.space2).padding(.horizontal, Socle.M.space3)
            .background(Socle.C.surfaceRaised)
            .overlay(alignment: .leading) { Rectangle().fill(Socle.C.warning).frame(width: 2) }
        }
    }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#5d5d64" }
        return String(format: "#%02x%02x%02x", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
