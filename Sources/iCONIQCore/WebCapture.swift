import Foundation

/// Icône repérée sur une page de portail (JSON renvoyé par le script de la page).
public struct CaptureCandidate: Codable, Hashable, Identifiable, Sendable {
    public var id: String { key }
    public var key: String
    public var kind: String      // "url" ou "svg"
    public var url: String       // adresse absolue (kind == url)
    public var svg: String       // balisage complet (kind == svg)
    public var name: String
    public var width: Int
    public var height: Int
}

public enum WebCapture {
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    public static func decode(_ json: String) -> [CaptureCandidate] {
        guard let d = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([CaptureCandidate].self, from: d)) ?? []
    }

    /// Adresse de recherche : le modèle contient `{q}`.
    public static func searchURL(template: String, query: String) -> URL? {
        guard template.contains("{q}") else { return nil }
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))) ?? query
        return URL(string: template.replacingOccurrences(of: "{q}", with: q))
    }

    /// Adresse saisie : ajoute https:// si besoin.
    public static func normalizeURL(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), let h = u.host, h.contains(".") || h == "localhost" else { return nil }
        return u
    }

    public static func cleanSVG(_ svg: String) -> String {
        var s = svg
        if !s.contains("xmlns=") { s = s.replacingOccurrences(of: "<svg", with: "<svg xmlns=\"http://www.w3.org/2000/svg\"", options: [], range: s.range(of: "<svg")) }
        s = s.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: "", options: .regularExpression)
        return s
    }

    /// Récupère les octets d'un candidat (téléchargement avec la page comme référent, ou SVG en ligne) et leur format.
    public static func fetch(_ c: CaptureCandidate, referer: String, cookies: [HTTPCookie] = []) async throws -> (data: Data, fmt: String) {
        if c.kind == "svg" { return (Data(cleanSVG(c.svg).utf8), "svg") }
        if c.url.hasPrefix("data:") { return try decodeDataURL(c.url) }
        guard let url = URL(string: c.url) else { throw DBError(message: "URL") }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        req.setValue("image/svg+xml,image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        for (k, v) in HTTPCookie.requestHeaderFields(with: cookies.filter { cookieMatches($0, url) }) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw DBError(message: "HTTP \(http.statusCode)") }
        let mime = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard let fmt = ImageMeta.sniff(data, hint: mime.isEmpty ? url.pathExtension : mime) ?? ImageMeta.sniff(data, hint: url.pathExtension) else { throw DBError(message: "format") }
        return (data, fmt)
    }

    static func cookieMatches(_ c: HTTPCookie, _ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let d = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
        return host == d || host.hasSuffix("." + d)
    }

    static func decodeDataURL(_ s: String) throws -> (Data, String) {
        guard let comma = s.firstIndex(of: ",") else { throw DBError(message: "data") }
        let meta = String(s[s.index(s.startIndex, offsetBy: 5)..<comma])
        let body = String(s[s.index(after: comma)...])
        let data: Data
        if meta.contains(";base64") { data = Data(base64Encoded: body) ?? Data() }
        else { data = (body.removingPercentEncoding ?? body).data(using: .utf8) ?? Data() }
        guard !data.isEmpty, let fmt = ImageMeta.sniff(data, hint: meta) else { throw DBError(message: "data") }
        return (data, fmt)
    }

    /// Nom lisible d'une icône d'après son texte alternatif ou le nom du fichier.
    public static func displayName(_ raw: String, fallbackURL: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty, let u = URL(string: fallbackURL) { n = u.deletingPathExtension().lastPathComponent }
        n = n.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "icon" : String(n.prefix(60))
    }
}

public enum CaptureScript {
    /// Liste les icônes de la page : <img>, <svg> (avec <use>), arrière-plans CSS et liens directs vers des SVG/PNG.
    public static let collect = #"""
    (function () {
      var out = [], seen = {};
      function abs(u) { try { return new URL(u, document.baseURI).href; } catch (e) { return ''; } }
      function push(c) { if (!c.key || seen[c.key]) return; seen[c.key] = 1; out.push(c); }
      function nm(el, u) {
        var e = el, i = 0;
        while (e && e.getAttribute && i++ < 4) {
          var v = e.getAttribute('alt') || e.getAttribute('title') || e.getAttribute('aria-label') || e.getAttribute('data-name') || e.getAttribute('data-icon') || e.getAttribute('data-tooltip');
          if (v) return v;
          e = e.parentElement;
        }
        var cls = (el.getAttribute && (el.getAttribute('class') || '')) || '', m = /(?:lucide|tabler-icon|icon|ph|bi|fa|mdi|ri)[-_]([a-z0-9][a-z0-9-]*)/i.exec(cls);
        if (m && !/^(svg|icon|lg|sm|md|xs)$/i.test(m[1])) return m[1];
        var a = el.closest && el.closest('a[href]');
        if (a) { var seg = a.getAttribute('href').split('?')[0].split('#')[0].split('/').filter(Boolean).pop(); if (seg && !/\.(html|php)$/i.test(seg) && seg.length < 40) return seg; }
        var t = el.parentElement && el.parentElement.textContent ? el.parentElement.textContent.trim() : '';
        return t.length > 0 && t.length < 30 ? t : '';
      }
      document.querySelectorAll('img').forEach(function (i) {
        var u = abs(i.currentSrc || i.src); if (!u) return;
        var w = i.naturalWidth || i.width, h = i.naturalHeight || i.height;
        if (w && h && (w < 12 || h < 12) && !/\.svg(\?|$)/i.test(u)) return;
        push({ key: u, kind: 'url', url: u, svg: '', name: nm(i, u), width: w | 0, height: h | 0 });
      });
      document.querySelectorAll('svg').forEach(function (s) {
        if (s.closest('svg') !== s) return;
        var r = s.getBoundingClientRect(); if (r.width < 12 || r.height < 12 || r.width > 1200) return;
        var c = s.cloneNode(true);
        c.querySelectorAll('use').forEach(function (u) {
          var href = u.getAttribute('href') || u.getAttribute('xlink:href'); if (!href || href[0] !== '#') return;
          var sym = document.querySelector(href); if (!sym) return;
          if (sym.tagName.toLowerCase() === 'symbol' && !c.getAttribute('viewBox') && sym.getAttribute('viewBox')) c.setAttribute('viewBox', sym.getAttribute('viewBox'));
          var g = document.createElementNS('http://www.w3.org/2000/svg', 'g'); g.innerHTML = sym.innerHTML; u.replaceWith(g);
        });
        c.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
        if (!c.getAttribute('viewBox') && r.width && r.height) c.setAttribute('viewBox', '0 0 ' + Math.round(r.width) + ' ' + Math.round(r.height));
        if (/currentColor/i.test(c.outerHTML)) c.setAttribute('color', '#000');
        c.removeAttribute('class'); c.removeAttribute('style');
        c.setAttribute('width', Math.round(r.width)); c.setAttribute('height', Math.round(r.height));
        var m = c.outerHTML; push({ key: 'svg:' + m.length + ':' + m.slice(0, 200) + m.slice(-100), kind: 'svg', url: '', svg: m, name: nm(s, ''), width: Math.round(r.width), height: Math.round(r.height) });
      });
      document.querySelectorAll('a[href]').forEach(function (a) {
        if (!/\.(svg|png)(\?|#|$)/i.test(a.getAttribute('href'))) return;
        var u = abs(a.getAttribute('href')); push({ key: u, kind: 'url', url: u, svg: '', name: a.getAttribute('title') || a.textContent.trim().slice(0, 40), width: 0, height: 0 });
      });
      var n = 0;
      document.querySelectorAll('*').forEach(function (e) {
        if (n++ > 4000) return;
        var b = getComputedStyle(e).backgroundImage; if (!b || b === 'none') return;
        var m = /url\(["']?([^"')]+)["']?\)/.exec(b); if (!m) return;
        var r = e.getBoundingClientRect(); if (r.width < 12 || r.height < 12 || r.width > 1200) return;
        var u = abs(m[1]); push({ key: u, kind: 'url', url: u, svg: '', name: nm(e, u), width: Math.round(r.width), height: Math.round(r.height) });
      });
      return JSON.stringify(out.slice(0, 1500));
    })()
    """#

    /// Remplit le champ de recherche du site et valide (portail sans modèle d'adresse de recherche).
    public static func search(_ q: String) -> String {
        let lit = (try? String(data: JSONEncoder().encode(q), encoding: .utf8)) ?? "\"\""
        return #"""
        (function (q) {
          var sel = 'input[type=search],input[name=q],input[name=query],input[name=search],input[name=s],input[name=word],input[placeholder*=earch i],input[aria-label*=earch i],input[type=text]';
          var list = Array.prototype.slice.call(document.querySelectorAll(sel)).filter(function (i) { var r = i.getBoundingClientRect(); return r.width > 40 && r.height > 10 && !i.disabled && i.type !== 'hidden'; });
          var i = list[0]; if (!i) return 'no';
          i.focus();
          var set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set; set.call(i, q);
          i.dispatchEvent(new Event('input', { bubbles: true })); i.dispatchEvent(new Event('change', { bubbles: true }));
          var ev = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
          i.dispatchEvent(new KeyboardEvent('keydown', ev)); i.dispatchEvent(new KeyboardEvent('keypress', ev)); i.dispatchEvent(new KeyboardEvent('keyup', ev));
          if (i.form) { try { i.form.requestSubmit(); } catch (e) { i.form.submit(); } }
          return 'ok';
        })(\#(lit))
        """#
    }

    /// Mode capture : survol encadré, clic = ajout (la page ne navigue pas).
    public static let captureMode = #"""
    (function () {
      if (window.__iconiq) return; var box = document.createElement('div');
      box.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:2px solid #f59e0b;background:rgba(245,158,11,.15);border-radius:4px;display:none';
      document.documentElement.appendChild(box);
      function target(e) { return e.target.closest && (e.target.closest('svg,img') || e.target); }
      function abs(u) { try { return new URL(u, document.baseURI).href; } catch (x) { return ''; } }
      function describe(el) {
        var r = el.getBoundingClientRect();
        if (el.tagName.toLowerCase() === 'img') { var u = abs(el.currentSrc || el.src); return { key: u, kind: 'url', url: u, svg: '', name: el.alt || el.title || '', width: el.naturalWidth | 0, height: el.naturalHeight | 0 }; }
        var s = el.closest('svg'); if (s) { var c = s.cloneNode(true); c.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
          if (!c.getAttribute('viewBox')) c.setAttribute('viewBox', '0 0 ' + Math.round(r.width) + ' ' + Math.round(r.height));
          if (/currentColor/i.test(c.outerHTML)) c.setAttribute('color', '#000');
          var m = c.outerHTML; return { key: 'svg:' + m.length + m.slice(0, 120), kind: 'svg', url: '', svg: m, name: s.getAttribute('aria-label') || '', width: Math.round(r.width), height: Math.round(r.height) }; }
        var b = getComputedStyle(el).backgroundImage, mm = /url\(["']?([^"')]+)["']?\)/.exec(b || '');
        if (mm) { var u2 = abs(mm[1]); return { key: u2, kind: 'url', url: u2, svg: '', name: el.getAttribute('title') || '', width: Math.round(r.width), height: Math.round(r.height) }; }
        return null;
      }
      document.addEventListener('mousemove', function (e) { var t = target(e), r = t.getBoundingClientRect(); box.style.display = 'block'; box.style.left = r.left + 'px'; box.style.top = r.top + 'px'; box.style.width = r.width + 'px'; box.style.height = r.height + 'px'; }, true);
      document.addEventListener('click', function (e) { var d = describe(target(e)); if (!d) return; e.preventDefault(); e.stopPropagation();
        window.webkit.messageHandlers.iconiqCapture.postMessage(JSON.stringify(d));
        box.style.background = 'rgba(34,197,94,.35)'; setTimeout(function () { box.style.background = 'rgba(245,158,11,.15)'; }, 250); }, true);
      window.__iconiq = { off: function () { box.remove(); window.__iconiq = null; } };
    })()
    """#
    public static let captureOff = "if (window.__iconiq) window.__iconiq.off();"
}
