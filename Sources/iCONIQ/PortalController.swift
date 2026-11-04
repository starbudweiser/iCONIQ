import AppKit
import SwiftUI
import WebKit
import iCONIQCore

/// Navigateur interne d'un portail d'icônes : page, détection des icônes, mode capture, téléchargements importés.
@MainActor
final class PortalController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    let portal: Portal
    let webView: WKWebView
    private unowned let model: AppModel

    @Published var address = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var loading = false
    @Published var candidates: [CaptureCandidate] = []
    @Published var picked: Set<String> = []
    @Published var showPanel = false
    @Published var detecting = false
    @Published var capture = false { didSet { setCapture() } }
    @Published var targetCollection: String?
    @Published var adding = false

    private var dataCache: [String: Data] = [:]
    private var pendingSearch: String?
    private var downloadTarget: [ObjectIdentifier: URL] = [:]

    init(portal: Portal, model: AppModel) {
        self.portal = portal; self.model = model
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        let proxy = ScriptProxy(self)
        cfg.userContentController.add(proxy, name: "iconiqCapture")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        if let u = URL(string: portal.url) { webView.load(URLRequest(url: u)) }
        targetCollection = model.collections.first { $0.kind == .portal && $0.name == portal.name }?.id
    }

    // MARK: Navigation

    func go(_ text: String) {
        guard let u = WebCapture.normalizeURL(text) else { model.say(L("portal.badURL"), error: true); return }
        webView.load(URLRequest(url: u))
    }

    func home() { if let u = URL(string: portal.url) { webView.load(URLRequest(url: u)) } }

    func search(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if let u = WebCapture.searchURL(template: portal.searchURL, query: q) { webView.load(URLRequest(url: u)); return }
        webView.evaluateJavaScript(CaptureScript.search(q)) { [weak self] r, _ in
            if (r as? String) != "ok" { Task { @MainActor in self?.model.say(L("portal.noSearchField"), error: true) } }
        }
    }

    private func refreshState() {
        address = webView.url?.absoluteString ?? address
        canGoBack = webView.canGoBack; canGoForward = webView.canGoForward; loading = webView.isLoading
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { refreshState(); candidates = []; picked = [] }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshState()
        if capture { setCapture() }
        if showPanel { detect(after: 1.2) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { refreshState() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { refreshState() }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        let disposition = http?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        decisionHandler(!navigationResponse.canShowMIMEType || disposition.contains("attachment") ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }

    // MARK: Téléchargements : importés directement dans iCONIQ

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iconiq-dl-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(suggestedFilename)
        downloadTarget[ObjectIdentifier(download)] = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloadTarget.removeValue(forKey: ObjectIdentifier(download)) else { return }
        Task { await importDownloaded(file) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadTarget[ObjectIdentifier(download)] = nil
        model.say(L("portal.download.failed"), error: true)
    }

    private func importDownloaded(_ file: URL) async {
        let ext = file.pathExtension.lowercased()
        let page = address
        guard let coll = ensureTarget() else { return }
        let lib = model.lib, name = portal.name
        var urls = [file]
        if ext == "zip" {
            let out = file.deletingLastPathComponent().appendingPathComponent("x")
            await Task.detached { _ = Updater.run("/usr/bin/ditto", ["-x", "-k", file.path, out.path]) }.value
            urls = (FileManager.default.enumerator(at: out, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
        }
        let ok = urls.filter { ImageMeta.supported.contains($0.pathExtension.lowercased()) }
        var n = 0
        for f in ok {
            guard let d = try? Data(contentsOf: f), let fmt = ImageMeta.sniff(d, hint: f.pathExtension) else { continue }
            if (try? lib.addIcon(data: d, fmt: fmt, name: f.deletingPathExtension().lastPathComponent, tags: name, collection: coll, pageURL: page)) != nil { n += 1 }
        }
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        model.reload()
        model.say(n > 0 ? L("toast.imported", n) : L("portal.download.nothing"), error: n == 0)
    }

    // MARK: Détection et capture

    func detect(after delay: Double = 0) {
        showPanel = true; detecting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.webView.evaluateJavaScript(CaptureScript.collect) { r, _ in
                Task { @MainActor in
                    self.detecting = false
                    self.candidates = WebCapture.decode((r as? String) ?? "[]")
                }
            }
        }
    }

    private func setCapture() {
        webView.evaluateJavaScript(capture ? CaptureScript.captureMode : CaptureScript.captureOff, completionHandler: nil)
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let s = message.body as? String, let d = s.data(using: .utf8), let c = try? JSONDecoder().decode(CaptureCandidate.self, from: d) else { return }
        Task { await add([c], quiet: false) }
    }

    func ensureTarget() -> String? {
        if let t = targetCollection, model.collections.contains(where: { $0.id == t }) { return t }
        guard let c = try? model.lib.collection(named: portal.name, kind: .portal, sourceURL: portal.url) else { return nil }
        targetCollection = c.id
        model.refreshSidebar()
        return c.id
    }

    func data(for c: CaptureCandidate) async -> Data? {
        if let d = dataCache[c.key] { return d }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard let r = try? await WebCapture.fetch(c, referer: address, cookies: cookies) else { return nil }
        dataCache[c.key] = r.data
        return r.data
    }

    func add(_ list: [CaptureCandidate], quiet: Bool) async {
        guard let coll = ensureTarget(), !list.isEmpty else { return }
        adding = true
        var ok = 0, fail = 0
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        for c in list {
            do {
                let (d, fmt) = try await WebCapture.fetch(c, referer: address, cookies: cookies)
                dataCache[c.key] = d
                let before = model.lib.totalCount()
                try model.lib.addIcon(data: d, fmt: fmt, name: WebCapture.displayName(c.name, fallbackURL: c.url), tags: portal.name, collection: coll,
                                      sourceURL: c.kind == "url" ? c.url : address, pageURL: address)
                if model.lib.totalCount() > before { ok += 1 }
            } catch { fail += 1 }
        }
        adding = false
        model.reload()
        if ok > 0 { model.say(L("portal.added", ok, model.collections.first { $0.id == coll }?.name ?? "")) }
        else if fail > 0 { model.say(L("portal.add.failed"), error: true) }
        else { model.say(L("portal.already")) }
        picked = []
    }
}

/// Évite que le contrôleur de contenu retienne le contrôleur du portail.
private final class ScriptProxy: NSObject, WKScriptMessageHandler {
    weak var target: PortalController?
    init(_ t: PortalController) { target = t }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.userContentController(ucc, didReceive: message) }
    }
}

struct WebHost: NSViewRepresentable {
    let controller: PortalController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ v: WKWebView, context: Context) {}
}
