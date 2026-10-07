//
//  KishoTheme.swift
//  Kisho
//
//  Outline-based look built on system semantic colours, so light and dark
//  mode need no special handling. Nesting is shown by indentation and
//  heading size alone. Shared by the Mac card editor, the sidebar rows and
//  the tag pills, and by the iOS editor to come.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum Theme {
    static let cornerRadius: CGFloat = 8

    // Each surface token comes in two forms: `Theme.x(theme)`, for views that
    // read `\.kishoEditorTheme` from the environment (so they redraw when the
    // theme changes), and the plain `Theme.x`, which reads the stored choice.

    /// Hairline for outlines and dividers.
    static func hairline(_ theme: EditorTheme) -> Color {
        theme == .sepia ? Color(red: 0.62, green: 0.54, blue: 0.42).opacity(0.45) : Color(platformColor: separator)
    }
    static var hairline: Color { hairline(.current) }

    /// Card face: the text background, so cards sit flush with the editor.
    static func cardBackground(_ theme: EditorTheme) -> Color {
        theme == .sepia ? Color(red: 0.985, green: 0.962, blue: 0.905) : Color(platformColor: textBackground)
    }
    static var cardBackground: Color { cardBackground(.current) }

    /// Editor canvas behind the cards: a step away from the card face so the
    /// outlines have something to sit against in both appearances.
    static func canvas(_ theme: EditorTheme) -> Color {
        theme == .sepia ? Color(red: 0.945, green: 0.912, blue: 0.838) : Color(platformColor: windowBackground)
    }
    static var canvas: Color { canvas(.current) }

    /// Sidebar and inspector surface. Sepia gets a slightly deeper paper than
    /// the canvas so the three areas read as separate; otherwise the system's.
    static func panel(_ theme: EditorTheme) -> Color {
        theme == .sepia ? Color(red: 0.918, green: 0.878, blue: 0.796) : Color(platformColor: windowBackground)
    }

    /// Text-entry fields in the panels (synopsis, notes): the card face.
    static func field(_ theme: EditorTheme) -> Color { cardBackground(theme) }

    /// Text view background for the card body (the AppKit/UIKit side of
    /// `cardBackground`, for the native text view).
    static var cardBackgroundPlatformColor: PlatformColor {
        EditorTheme.current == .sepia ? PlatformColor(red: 0.985, green: 0.962, blue: 0.905, alpha: 1) : textBackground
    }

    // The semantic colours each platform calls something different.

    private static var separator: PlatformColor {
        #if canImport(AppKit)
        return .separatorColor
        #else
        return .separator
        #endif
    }

    private static var textBackground: PlatformColor {
        #if canImport(AppKit)
        return .textBackgroundColor
        #else
        return .systemBackground
        #endif
    }

    private static var windowBackground: PlatformColor {
        #if canImport(AppKit)
        return .windowBackgroundColor
        #else
        return .secondarySystemBackground
        #endif
    }
}


// MARK: - Themed panels

/// Paints the sidebar / inspector surface in the editor theme. Light, dark
/// and system follow the system appearance (which is applied app-wide), so
/// by default only Sepia paints anything and the system's own sidebar
/// material or grouped background shows through otherwise. The Mac inspector
/// has no system surface of its own, so it paints always.
struct ThemedPanel: ViewModifier {
    @ThemeSetting private var theme
    let alwaysPaint: Bool

    func body(content: Content) -> some View {
        if alwaysPaint || theme == .sepia {
            content.background(Theme.panel(theme).ignoresSafeArea())
        } else {
            content
        }
    }
}

extension View {
    func themedPanel(alwaysPaint: Bool = false) -> some View {
        modifier(ThemedPanel(alwaysPaint: alwaysPaint))
    }
}
