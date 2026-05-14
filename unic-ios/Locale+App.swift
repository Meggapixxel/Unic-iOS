import Foundation

enum AppLanguage: String, CaseIterable, Equatable, Identifiable {
    var id: String { rawValue }
    case en = "en"
    case ua = "uk"
    case ru = "ru"

    var label: String {
        switch self {
        case .en: return "EN"
        case .ua: return "UA"
        case .ru: return "RU"
        }
    }
}

extension Locale {
    var appLanguage: AppLanguage {
        switch language.languageCode?.identifier {
        case "uk": return .ua
        case "ru": return .ru
        default:   return .en
        }
    }
}
