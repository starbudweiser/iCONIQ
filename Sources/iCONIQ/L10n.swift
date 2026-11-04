import Foundation

/// Texte traduit (Resources/<langue>.lproj/Localizable.strings : fr, en, es, it) ; langue du système, anglais sinon.
func L(_ key: String, _ args: CVarArg...) -> String {
    let text = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? text : String(format: text, locale: Locale.current, arguments: args)
}

enum Lang {
    /// Code de la langue affichée (fr, en, es, it), pour le moteur de mise à jour.
    static var code: String { Bundle.main.preferredLocalizations.first ?? "en" }
}
