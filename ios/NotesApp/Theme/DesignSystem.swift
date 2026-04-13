// ios/NotesApp/Theme/DesignSystem.swift
import SwiftUI

enum AppColors {
    // Backgrounds
    static let bg       = Color(hex: "#0A0A0C")!
    static let surface  = Color(hex: "#141416")!
    static let surface2 = Color(hex: "#1C1C1E")!
    static let surface3 = Color(hex: "#242426")!

    // Borders
    static let border  = Color(hex: "#2A2A2E")!
    static let border2 = Color(hex: "#333338")!

    // Gold accent
    static let gold      = Color(hex: "#C9A84C")!
    static let goldDark  = Color(hex: "#A87C28")!
    static let goldLight = Color(hex: "#E8C96A")!
    static var goldGradient: LinearGradient {
        LinearGradient(colors: [gold, goldDark],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Text
    static let textPrimary   = Color(hex: "#F0EDE6")!
    static let textSecondary = Color(hex: "#A0A0A8")!
    static let textTertiary  = Color(hex: "#606068")!

    // Canvas — always light so ink is readable
    static let canvasPaper = Color(hex: "#FAF8F3")!
    static let canvasRuled = Color(hex: "#C8D4D8")!
}

enum AppFonts {
    static let navTitle      = Font.system(size: 17, weight: .bold)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let body          = Font.system(size: 14, weight: .regular)
    static let bodyBold      = Font.system(size: 14, weight: .semibold)
    static let caption       = Font.system(size: 11, weight: .regular)
    static let micro         = Font.system(size: 9,  weight: .regular)
}

enum AppRadius {
    static let card:   CGFloat = 10
    static let button: CGFloat = 9
    static let chip:   CGFloat = 8
    static let thumb:  CGFloat = 6
}

enum AppSpacing {
    static let page:  CGFloat = 18
    static let grid:  CGFloat = 16
    static let stack: CGFloat = 10
}

// MARK: - Color hex initialiser (canonical, used everywhere)
extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >>  8) & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}

// MARK: - Cover gradient helpers
/// Notebook covers store their gradient as "START_HEX|END_HEX".
/// Falls back to a solid color for legacy single-hex values.
extension String {
    var asCoverGradient: LinearGradient {
        let parts = self.split(separator: "|").map(String.init)
        if parts.count == 2,
           let c1 = Color(hex: parts[0]),
           let c2 = Color(hex: parts[1]) {
            return LinearGradient(colors: [c1, c2],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        let c = Color(hex: self) ?? AppColors.gold
        return LinearGradient(colors: [c, c],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
