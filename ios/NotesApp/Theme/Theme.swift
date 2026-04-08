import SwiftUI

enum ThemePreference: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    static func fromStorage(_ raw: String) -> ThemePreference {
        ThemePreference(rawValue: raw) ?? .system
    }
}
