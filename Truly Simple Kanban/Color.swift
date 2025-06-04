// Color.swift
import SwiftUI

extension Color {
    // New Palette: White app background, very light gray columns
    static let appBackground = Color.white // Or Color(hex: "FAFAFA") for a hint of off-white
    static let columnBackground = Color(UIColor.systemGray6) // This is a very light system gray
    static let cardBackground = Color.white // Cards will be white, relying on borders/column color for separation

    // Text and border colors can remain or be slightly adjusted
    static let primaryText = Color(UIColor.darkGray)
    static let secondaryText = Color(UIColor.gray)
    static let subtleBorder = Color(UIColor.systemGray4).opacity(0.7) // Slightly more visible border for white-on-white
    
    // System accent for placeholders, or choose a custom one
    // static let placeholderLine = Color.accentColor.opacity(0.3) // Default system accent
    static let placeholderLine = Color.gray.opacity(0.3) // A neutral gray placeholder
}

// Optional: Hex color initializer (if you had it before, keep it)
// extension Color {
//     init(hex: String) { ... }
// }
