import SwiftUI
import AppKit

enum Brand {
    /// Violet du logo : la lettre « i » d'iCONIQ.
    static let color = Color(red: 0x8b / 255, green: 0x5c / 255, blue: 0xf6 / 255)
    static let nsColor = NSColor(srgbRed: 0x8b / 255, green: 0x5c / 255, blue: 0xf6 / 255, alpha: 1)
}

/// Motif de l'icône (quatre tuiles, l'une pleine), d'une seule teinte : logo, état vide.
struct IconiqMark: View {
    var body: some View {
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 640
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let tile: CGFloat = 250 * k, gap: CGFloat = 40 * k
            for (i, (dx, dy)) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)].enumerated() {
                let r = CGRect(x: c.x + (dx > 0 ? gap / 2 : -gap / 2 - tile), y: c.y + (dy > 0 ? gap / 2 : -gap / 2 - tile), width: tile, height: tile)
                let p = Path(roundedRect: r, cornerRadius: 56 * k)
                if i == 3 { ctx.fill(p, with: .foreground) } else { ctx.stroke(p, with: .foreground, lineWidth: 26 * k) }
            }
        }
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(branded: text).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true) }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            Text(title).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
            content
        }
        .padding(Socle.M.space6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(Socle.C.border, lineWidth: 1))
    }
}

struct Check: View {
    let title: String
    var help: String?
    @Binding var isOn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $isOn) { Text(title).socle(Socle.T.body).foregroundStyle(Socle.C.text).fixedSize(horizontal: false, vertical: true) }
                .toggleStyle(.checkbox).tint(Socle.C.accent)
            if let help { Hint(help).padding(.leading, 22) }
        }
    }
}

/// Bouton d'icône de barre d'outils (symbole SF), fond de survol Socle.
struct BarButton: View {
    let symbol: String
    var help: String = ""
    var active = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Socle.C.accentText : Socle.C.textMuted)
                .frame(width: Socle.M.sizeControl, height: Socle.M.sizeControl)
                .background(hover || active ? Socle.C.control : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        }
        .buttonStyle(.plain).onHover { hover = $0 }.help(help)
    }
}

/// Champ de recherche Socle avec loupe.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    var body: some View {
        HStack(spacing: Socle.M.space2) {
            Image(systemName: "magnifyingglass").foregroundStyle(Socle.C.textSubtle).font(.system(size: 12))
            TextField(prompt, text: $text).textFieldStyle(.plain).socle(Socle.T.body).foregroundStyle(Socle.C.textStrong).onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Socle.C.textSubtle) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Socle.M.space3)
        .frame(height: Socle.M.sizeControl)
        .background(Socle.C.bgSunken)
    }
}

struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Socle.C.bgSunken)
                Rectangle().fill(Socle.C.accent).frame(width: g.size.width * max(0.02, min(1, fraction)))
            }
        }.frame(height: 6)
    }
}

struct ToastView: View {
    let toast: Toast
    var body: some View {
        Text(toast.text).socle(Socle.T.label).foregroundStyle(toast.error ? Socle.C.dangerSoft : Socle.C.textStrong)
            .padding(.horizontal, Socle.M.space4).padding(.vertical, Socle.M.space2_5)
            .background(toast.error ? Socle.C.dangerBg : Socle.C.surfaceRaised, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(toast.error ? Socle.C.dangerBorder : Socle.C.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

/// Fenêtre principale : taille minimale qui évite tout chevauchement ou retour à la ligne des boutons, et centrage au lancement.
struct WindowConfigurator: NSViewRepresentable {
    static let minSize = NSSize(width: 1120, height: 680)
    static let defaultSize = NSSize(width: 1320, height: 840)

    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        private var done = false
        override func viewDidMoveToWindow() {
            guard !done, let w = window else { return }
            done = true
            w.isRestorable = false
            w.contentMinSize = WindowConfigurator.minSize
            // SwiftUI restaure sa propre taille juste après l'affichage : on impose la nôtre au tour suivant.
            DispatchQueue.main.async { [weak w] in
                guard let w else { return }
                let zone = (w.screen ?? NSScreen.main)?.visibleFrame.size ?? WindowConfigurator.defaultSize
                w.setContentSize(NSSize(width: min(WindowConfigurator.defaultSize.width, zone.width), height: min(WindowConfigurator.defaultSize.height, zone.height - 40)))
                w.socleCenter()
            }
        }
    }
}
