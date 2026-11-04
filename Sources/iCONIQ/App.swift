import SwiftUI
import iCONIQCore

@main
struct IconiqApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("iCONIQ", id: "main") {
            RootView(model: model)
                .onOpenURL { url in handle(url) }
        }
        .defaultSize(width: WindowConfigurator.defaultSize.width, height: WindowConfigurator.defaultSize.height)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("about.menu")) { About.show() }
                Button(L("upd.menu")) { UpdateEngine.shared.checkNow() }
            }
            CommandGroup(replacing: .newItem) {
                Button(L("import.iconjar")) { model.chooseImport(.iconjar) }.keyboardShortcut("i", modifiers: [.command])
                Button(L("import.folder")) { model.chooseImport(.folder) }.keyboardShortcut("i", modifiers: [.command, .shift])
                Button(L("import.files")) { model.chooseImport(.files) }
                Divider()
                Button(L("side.newCollection")) { model.newCollection(name: L("side.newCollection.default")) }.keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .toolbar) {
                Button(L("lib.inspector")) { model.inspectorOpen.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        Settings { SettingsView(model: model) }
    }

    private func handle(_ url: URL) {
        if url.scheme == "iconiq" { model.processInbox(); return }
        if url.isFileURL { model.importURLs([url]) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        Socle.brand("iCONIQ", color: Brand.color)
        let model = AppModel.shared
        model.startInbox()
        // Essais : `--import <chemin>` importe une bibliothèque IconJar ou un dossier au lancement ; `--portal <adresse>` ouvre un portail.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--import"), i + 1 < args.count { model.importURLs([URL(fileURLWithPath: args[i + 1])]) }
        let updates = UpdateEngine.shared
        updates.configure(repo: "iCONIQ", lang: { Lang.code })
        updates.autoCheck = { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
        updates.canInstall = { AppModel.shared.progress == nil }
        updates.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Le schéma iconiq:// et les bibliothèques IconJar ouvertes depuis le Finder.
        for u in urls { if u.scheme == "iconiq" { AppModel.shared.processInbox() } else { AppModel.shared.importURLs([u]) } }
    }
}
