import SwiftUI

/// Design tokens. Use these instead of literal values in feature views.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let chip: CGFloat = 16
    static let card: CGFloat = 14
}

enum Layout {
    /// Apple HIG minimum touch target.
    static let minTouchTarget: CGFloat = 44
    /// Comfortable reading measure for article text on wide screens.
    static let readableWidth: CGFloat = 680
}

enum Palette {
    static let accent = Color.accentColor
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let screenBackground = Color(uiColor: .systemGroupedBackground)
    static let chipBackground = Color(uiColor: .tertiarySystemFill)
    static let secondaryText = Color.secondary
    /// Used with an icon + text label; never as the only signal.
    static let generatedContent = Color.purple
    static let sample = Color.orange
}

enum Typography {
    static let cardTitle = Font.headline
    static let meta = Font.caption
    static let articleTitle = Font.title2.weight(.bold)
    static let articleBody = Font.body
    static let sectionHeader = Font.title3.weight(.semibold)
}
