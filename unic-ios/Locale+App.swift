import Foundation

extension Locale {
    var appLanguage: String {
        let code = language.languageCode?.identifier ?? "uk"
        return ["en", "uk", "ru"].contains(code) ? code : "uk"
    }
}
