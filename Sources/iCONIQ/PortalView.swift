import SwiftUI
import iCONIQCore

struct PortalView: View {
    @ObservedObject var model: AppModel
    let portal: Portal

    var body: some View {
        PortalInner(model: model, portal: portal, ctl: model.controller(for: portal))
    }
}

private struct PortalInner: View {
    @ObservedObject var model: AppModel
    let portal: Portal
    @ObservedObject var ctl: PortalController
    @State private var query = ""
    @State private var addressText = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            bar
            Rectangle().fill(Socle.C.border).frame(height: 1)
            HStack(spacing: 0) {
                ZStack {
                    WebHost(controller: ctl)
                    if ctl.capture {
                        VStack { Spacer(); Text(L("portal.capture.hint")).socle(Socle.T.label).foregroundStyle(Socle.C.onAction)
                            .padding(.horizontal, Socle.M.space4).padding(.vertical, Socle.M.space2).background(Socle.C.action, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd)).padding(.bottom, Socle.M.space4) }
                            .allowsHitTesting(false)
                    }
                }
                if ctl.showPanel {
                    Rectangle().fill(Socle.C.border).frame(width: 1)
                    CandidatesPanel(model: model, ctl: ctl).frame(width: 330)
                }
            }
        }
        .onChange(of: ctl.address) { _, v in if !addressFocused { addressText = v } }
        .onAppear { addressText = ctl.address }
    }

    private var bar: some View {
        HStack(spacing: Socle.M.space2) {
            BarButton(symbol: "chevron.left", help: L("portal.back")) { ctl.webView.goBack() }.disabled(!ctl.canGoBack)
            BarButton(symbol: "chevron.right", help: L("portal.forward")) { ctl.webView.goForward() }.disabled(!ctl.canGoForward)
            BarButton(symbol: ctl.loading ? "xmark" : "arrow.clockwise", help: L("portal.reload")) { if ctl.loading { ctl.webView.stopLoading() } else { ctl.webView.reload() } }
            BarButton(symbol: "house", help: L("portal.home")) { ctl.home() }
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(Socle.C.textSubtle)
                TextField(L("portal.address"), text: $addressText).textFieldStyle(.plain).socle(Socle.T.body).foregroundStyle(Socle.C.accentText)
                    .focused($addressFocused).onSubmit { ctl.go(addressText) }
            }
            .padding(.horizontal, Socle.M.space3).frame(height: Socle.M.sizeControl).background(Socle.C.bgSunken)
            SearchField(prompt: L("portal.search", portal.name), text: $query) { ctl.search(query) }.frame(width: 230)
            BarButton(symbol: "scope", help: L("portal.capture.help"), active: ctl.capture) { ctl.capture.toggle() }
            Button(L("portal.detect")) { ctl.detect() }
                .buttonStyle(SocleButtonStyle(.action, height: Socle.M.sizeControl)).fixedSize()
        }
        .padding(.horizontal, Socle.M.space3).frame(height: Socle.M.sizeBar + 14).background(Socle.C.surfaceRaised)
    }
}

struct CandidatesPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ctl: PortalController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("cand.title")).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                Text("\(ctl.candidates.count)").socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle)
                Spacer()
                BarButton(symbol: "arrow.clockwise", help: L("cand.refresh")) { ctl.detect() }
                BarButton(symbol: "xmark", help: L("common.close")) { ctl.showPanel = false }
            }
            .padding(.horizontal, Socle.M.space3).frame(height: Socle.M.sizeBar + 14)
            Rectangle().fill(Socle.C.border).frame(height: 1)
            if ctl.detecting {
                Spacer(); ProgressView().controlSize(.small); Spacer()
            } else if ctl.candidates.isEmpty {
                Spacer(); Text(L("cand.none")).socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle).multilineTextAlignment(.center).padding(Socle.M.space6); Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: Socle.M.space2)], spacing: Socle.M.space2) {
                        ForEach(ctl.candidates) { c in CandidateCell(ctl: ctl, c: c, picked: ctl.picked.contains(c.key)) }
                    }.padding(Socle.M.space3)
                }
            }
            Rectangle().fill(Socle.C.border).frame(height: 1)
            VStack(spacing: Socle.M.space2) {
                HStack {
                    Text(L("cand.into")).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                    Picker("", selection: Binding(get: { ctl.targetCollection ?? "" }, set: { ctl.targetCollection = $0.isEmpty ? nil : $0 })) {
                        Text(L("cand.into.default", ctl.portal.name)).tag("")
                        ForEach(model.collections) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                HStack(spacing: Socle.M.space2) {
                    Button(ctl.picked.count == ctl.candidates.count ? L("cand.none.all") : L("cand.all")) {
                        ctl.picked = ctl.picked.count == ctl.candidates.count ? [] : Set(ctl.candidates.map(\.key))
                    }.buttonStyle(SocleButtonStyle(.secondary)).disabled(ctl.candidates.isEmpty)
                    Button(ctl.picked.isEmpty ? L("cand.add") : L("cand.add.n", ctl.picked.count)) {
                        let list = ctl.candidates.filter { ctl.picked.contains($0.key) }
                        Task { await ctl.add(list, quiet: false) }
                    }.buttonStyle(SocleButtonStyle(.primary)).disabled(ctl.picked.isEmpty || ctl.adding)
                }
                .lineLimit(1)
            }.padding(Socle.M.space3)
        }
        .background(Socle.C.surfaceRaised)
    }
}

struct CandidateCell: View {
    @ObservedObject var ctl: PortalController
    let c: CaptureCandidate
    let picked: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: Socle.M.radius).fill(Color(white: 0.955))
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(12) } else { ProgressView().controlSize(.small) }
            Image(systemName: picked ? "checkmark.circle.fill" : "circle").font(.system(size: 13))
                .foregroundStyle(picked ? Socle.C.accent : Color.gray.opacity(0.6)).padding(4)
        }
        .frame(height: 84)
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radius).stroke(picked ? Socle.C.accent : .clear, lineWidth: 2))
        .help(c.name.isEmpty ? (c.width > 0 ? "\(c.width)×\(c.height)" : c.url) : c.name)
        .onTapGesture { if picked { ctl.picked.remove(c.key) } else { ctl.picked.insert(c.key) } }
        .task(id: c.key) {
            if let d = await ctl.data(for: c) { image = NSImage(data: d) }
        }
    }
}

// MARK: - Fiche portail

struct PortalSheet: View {
    @ObservedObject var model: AppModel
    @State var portal: Portal
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, portal: Portal) { self.model = model; _portal = State(initialValue: portal) }

    private var valid: Bool { !portal.name.trimmingCharacters(in: .whitespaces).isEmpty && WebCapture.normalizeURL(portal.url) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            Text(model.portals.contains { $0.id == portal.id } ? L("portal.edit") : L("portal.add")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            field(L("portal.field.name")) { TextField("Flaticon", text: $portal.name).socleField() }
            field(L("portal.field.url")) { TextField("https://www.flaticon.com", text: $portal.url).socleField() }
            field(L("portal.field.search")) {
                TextField("https://…/search?q={q}", text: $portal.searchURL).socleField()
                Hint(L("portal.field.search.help"))
            }
            HStack(spacing: Socle.M.space2) {
                Button(L("common.cancel")) { dismiss() }.buttonStyle(SocleButtonStyle(.secondary))
                Button(L("common.save")) {
                    var p = portal
                    p.name = p.name.trimmingCharacters(in: .whitespaces)
                    p.url = WebCapture.normalizeURL(p.url)?.absoluteString ?? p.url
                    p.searchURL = p.searchURL.trimmingCharacters(in: .whitespaces)
                    model.lib.savePortal(p); model.refreshSidebar(); model.item = .portal(p.id); dismiss()
                }.buttonStyle(SocleButtonStyle(.primary)).disabled(!valid)
            }
        }
        .padding(Socle.M.space6).frame(width: 480).background(Socle.C.surface)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).socle(Socle.T.label).foregroundStyle(Socle.C.textMuted); content() }
    }
}
