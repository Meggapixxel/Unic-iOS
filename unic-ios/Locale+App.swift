import Foundation

/// The set of content languages supported by the app for promo localisation.
enum AppLanguage: String, CaseIterable, Equatable, Identifiable {
    var id: String { rawValue }
    case en = "en"
    case ua = "uk"
    case ru = "ru"

    /// Short uppercase display label shown in language pickers (e.g. `"EN"`, `"UA"`).
    var label: String {
        switch self {
        case .en: return "EN"
        case .ua: return "UA"
        case .ru: return "RU"
        }
    }
}

extension Locale {
    /// Maps the current `Locale` to the nearest supported `AppLanguage`, defaulting to `.en`.
    var appLanguage: AppLanguage {
        switch language.languageCode?.identifier {
        case "uk": return .ua
        case "ru": return .ru
        default:   return .en
        }
    }
}
