import AppKit
import Foundation
import IconiqMCPCore

// `iconiq-mcp` : transport stdio (JSON-RPC 2.0, une ligne par message) du serveur MCP d'iCONIQ. Il ne lance pas iCONIQ et
// n'affiche aucune fenêtre ; tout est traité sur le fil principal (la pose d'icône passe par AppKit).
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
let server = MCPServer()
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
    guard let reply = autoreleasepool(invoking: { server.handle(object) }),
          let out = try? JSONSerialization.data(withJSONObject: reply, options: [.withoutEscapingSlashes]),
          let text = String(data: out, encoding: .utf8) else { continue }
    print(text); fflush(stdout)
}
