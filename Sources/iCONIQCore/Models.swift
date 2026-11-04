import Foundation

public struct IconGroup: Identifiable, Hashable, Sendable {
    public var id: String
    public var parent: String?
    public var name: String
    public var sort: Int
}

public enum CollectionKind: String, Sendable { case normal, micone, portal }

public struct IconCollection: Identifiable, Hashable, Sendable {
    public var id: String
    public var group: String?
    public var name: String
    public var author: String
    public var sourceURL: String
    public var license: String
    public var kind: CollectionKind
    public var sort: Int
    public var count: Int = 0
}

public struct Icon: Identifiable, Hashable, Sendable {
    public var id: String
    public var collection: String
    public var name: String
    public var tags: String
    public var file: String           // nom du fichier dans Files/<collection>/
    public var fmt: String            // svg, png, jpg, gif, webp, icns, pdf, ico
    public var width: Int
    public var height: Int
    public var starred: Bool
    public var lastUsed: Date?
    public var added: Date
    public var sourceURL: String
    public var pageURL: String
    public var linkPath: String       // fichier d'origine suivi (lien MiCONE)
    public var info: String

    public var tagList: [String] { tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

public struct Portal: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var searchURL: String      // modèle avec {q}, vide = recherche par le champ du site
    public var sort: Int

    public init(id: String, name: String, url: String, searchURL: String, sort: Int) {
        self.id = id; self.name = name; self.url = url; self.searchURL = searchURL; self.sort = sort
    }
}

public enum Scope: Hashable, Sendable {
    case all, starred, recent, micone
    case collection(String)
    case group(String)
}

public enum IconSort: String, Sendable { case name, added, size }

public struct IconQuery: Sendable {
    public var scope: Scope = .all
    public var text: String = ""
    public var sort: IconSort = .name
    public init(scope: Scope = .all, text: String = "", sort: IconSort = .name) {
        self.scope = scope; self.text = text; self.sort = sort
    }
}

public enum Norm {
    /// Minuscules sans accents, pour la recherche.
    public static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }
}
