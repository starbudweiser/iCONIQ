import AppKit
import Foundation
import iCONIQCore
import MiCONECore

/// Serveur MCP d'iCONIQ (JSON-RPC 2.0, indépendant du transport). Fabrique les icônes avec le moteur de MiCONE, les pose sur des
/// dossiers et les range dans la bibliothèque d'iCONIQ, appli ouverte ou fermée. Tout se fait sur le fil principal (pose d'icône AppKit).
public final class MCPServer {
    public let root: URL
    public var clientName = "unknown"
    private var lib: Library?

    public init(root: URL = Library.defaultRoot) { self.root = root }

    public static let instructions = """
    iCONIQ is the user's icon library; it also makes macOS icons with MiCONE's engine. Typical flow when a new app is created: \
    library_suggest_collection (for kind app and folder) -> ask the user to confirm or pick another collection (library_list) -> \
    icons_app_kit with the app's 1024 px image, the app's folder and the confirmed collections. It makes the app icon and the Finder-style folder icon, \
    sets the folder icon (the previous custom icon is backed up) and files both icons in the library. Other tools: icons_make, icons_apply_to_folder, \
    icons_clear_folder_icon, library_list, library_create_collection, library_create_group, library_add_icon, library_search, library_get_icon. \
    Nothing is ever deleted and nothing is sent over the network.
    """

    // MARK: JSON-RPC

    public func handle(_ message: [String: Any]) -> [String: Any]? {
        guard let method = message["method"] as? String, let id = message["id"] else { return nil }
        func reply(_ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        func fail(_ code: Int, _ text: String) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]] }
        switch method {
        case "initialize":
            let params = message["params"] as? [String: Any]
            if let info = params?["clientInfo"] as? [String: Any], let n = info["name"] as? String, !n.isEmpty { clientName = n }
            return reply(["protocolVersion": params?["protocolVersion"] as? String ?? "2025-03-26", "capabilities": ["tools": [String: Any]()],
                          "serverInfo": ["name": "iconiq", "version": "1.0.0"], "instructions": Self.instructions])
        case "ping": return reply([:])
        case "tools/list": return reply(["tools": Tools.schemas])
        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard Tools.names.contains(name) else { return fail(-32602, "Unknown tool: \(name)") }
            let out = call(name, args)
            return reply(["content": out.content, "isError": out.isError])
        default: return fail(-32601, "Method not found: \(method)")
        }
    }

    public struct Output { public var content: [[String: Any]]; public var isError: Bool }

    /// Exécute un outil après contrôle de l'accord ; journalise l'appel et son résultat.
    public func call(_ name: String, _ args: [String: Any]) -> Output {
        if let refus = authorize() { MCPStore.log("\(clientName)\t\(name)\trefused", root); return Output(content: [text(refus)], isError: true) }
        do {
            let (result, images) = try Tools(server: self).run(name, args)
            MCPStore.log("\(clientName)\t\(name)\t\(Self.summary(args))\tok", root)
            return Output(content: [text(Self.json(result))] + images.map { ["type": "image", "data": $0.base64EncodedString(), "mimeType": "image/png"] }, isError: false)
        } catch {
            MCPStore.log("\(clientName)\t\(name)\t\(Self.summary(args))\terror: \(error.localizedDescription)", root)
            return Output(content: [text(error.localizedDescription)], isError: true)
        }
    }

    /// nil si autorisé, sinon le message renvoyé à l'agent. Un client inconnu est mis en attente d'accord dans iCONIQ.
    func authorize() -> String? {
        let s = MCPStore.load(root)
        guard s.enabled else {
            return "AI control is off in iCONIQ. Ask the user to open iCONIQ › Settings › AI control and turn on \"Allow AI control\". It is off by default so that no program can change icons without the user's consent."
        }
        switch s.clients[clientName] {
        case .allowed: return nil
        case .denied: return "The user refused access to \"\(clientName)\" in iCONIQ › Settings › AI control."
        default:
            let c = clientName
            MCPStore.update(root) { if $0.clients[c] == nil { $0.clients[c] = .pending } }
            return "Waiting for the user's approval: ask them to allow \"\(clientName)\" in iCONIQ › Settings › AI control (or in the banner of the iCONIQ window), then call the tool again."
        }
    }

    func library() throws -> Library {
        if let lib { return lib }
        let l = try Library(root: root); lib = l; return l
    }

    func libraryChanged() { MCPStore.post(MCPStore.libraryChanged) }

    // MARK: Utilitaires

    private func text(_ s: String) -> [String: Any] { ["type": "text", "text": s] }

    static func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "\(o)" }
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    static func summary(_ args: [String: Any]) -> String {
        args.keys.sorted().compactMap { k in
            let v = args[k].map { "\($0)" } ?? ""
            return "\(k)=\(v.count > 60 ? "…" + v.suffix(57) : v)"
        }.joined(separator: " ")
    }
}

public struct MCPError: LocalizedError {
    public let message: String
    public init(_ m: String) { message = m }
    public var errorDescription: String? { message }
}
