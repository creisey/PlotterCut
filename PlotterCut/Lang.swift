import Foundation

nonisolated enum Lang: String, CaseIterable, Identifiable {
    case de, en
    var id: String { rawValue }
    var label: String { self == .de ? "Deutsch" : "English" }
}

/// Einfache Übersetzung: L.t("Deutsch", "English")
nonisolated enum L {
    static let key = "PlotterCutLanguage"
    nonisolated(unsafe) static var lang: Lang =
        Lang(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .de
    static func t(_ de: String, _ en: String) -> String { lang == .en ? en : de }
}
