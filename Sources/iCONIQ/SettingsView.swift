import SwiftUI
import iCONIQCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates = UpdateEngine.shared
    @AppStorage("autoUpdate") private var auto = true
    @State private var miconeURL: URL? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MiCONELink.bundleID)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
                Card(title: L("set.micone.title")) {
                    HStack(spacing: Socle.M.space2) {
                        Circle().fill(miconeURL != nil ? Socle.C.success : Socle.C.textDisabled).frame(width: 8, height: 8)
                        Text(miconeURL != nil ? L("set.micone.found") : L("set.micone.missing")).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                    }
                    Hint(L("set.micone.help"))
                    HStack(spacing: Socle.M.space2) {
                        Button(L("set.micone.open")) { if let u = miconeURL { NSWorkspace.shared.openApplication(at: u, configuration: { let c = NSWorkspace.OpenConfiguration(); c.activates = false; return c }()) } }
                            .buttonStyle(SocleButtonStyle(.secondary)).disabled(miconeURL == nil)
                        Button(L("set.micone.inbox")) { NSWorkspace.shared.activateFileViewerSelecting([model.lib.inboxDir]) }.buttonStyle(SocleButtonStyle(.secondary))
                    }
                    Hint(model.lib.inboxDir.path)
                }
                Card(title: L("set.library.title")) {
                    Hint(L("set.library.count", model.total, model.collections.count))
                    Hint(model.lib.root.path)
                    HStack(spacing: Socle.M.space2) {
                        Button(L("set.library.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([model.lib.root]) }.buttonStyle(SocleButtonStyle(.secondary))
                        Button(L("set.library.cache")) {
                            try? FileManager.default.removeItem(at: model.lib.cacheDir.appendingPathComponent("thumbs")); Thumbs.shared.forget(); model.reload(); model.say(L("set.library.cache.done"))
                        }.buttonStyle(SocleButtonStyle(.secondary))
                    }
                }
                Card(title: L("set.portals.title")) {
                    Hint(L("set.portals.help"))
                    Button(L("portal.add")) { model.portalSheet = Portal(id: UUID().uuidString, name: "", url: "", searchURL: "", sort: model.portals.count) }
                        .buttonStyle(SocleButtonStyle(.secondary)).frame(width: 220)
                }
                Card(title: L("upd.title")) { UpdateSection(updates: updates, auto: $auto) }
            }
            .padding(Socle.M.space6)
        }
        .frame(width: 560, height: 640)
        .background(Socle.C.bg)
    }
}

struct UpdateSection: View {
    @ObservedObject var updates: UpdateEngine
    @Binding var auto: Bool

    private var status: String {
        switch updates.state {
        case .idle: return L("upd.version", updates.currentVersion)
        case .checking: return L("upd.checking")
        case .upToDate: return L("upd.uptodate", updates.currentVersion)
        case .available(let plan): return L("upd.available", plan.target.version)
        case .downloading, .verifying, .installing: return L("upd.installing")
        case .failed: return L("upd.failed")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            Check(title: L("upd.auto"), isOn: $auto)
            Button(L("upd.check")) { updates.checkNow() }
                .buttonStyle(SocleButtonStyle(.secondary)).frame(width: 260).disabled(updates.isBusy)
            Hint(status)
        }
    }
}

enum MiCONELink {
    static let bundleID = "fr.stephan.micone"
}
