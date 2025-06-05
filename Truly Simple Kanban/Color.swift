// Color.swift
import SwiftUI

extension Color {
    // Palette updated for adaptive light/dark mode
    static let appBackground = Color(UIColor.systemBackground)
    static let columnBackground = Color(UIColor.systemGray6) // systemGray6 is adaptive
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground) // Good for cards

    static let primaryText = Color(UIColor.label)
    static let secondaryText = Color(UIColor.secondaryLabel)
    static let subtleBorder = Color(UIColor.separator) // Adaptive separator color
    
    static let placeholderLine = Color(UIColor.tertiaryLabel) // Adaptive, subtle placeholder
}
