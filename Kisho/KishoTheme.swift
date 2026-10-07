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

    /// Block titles are drawn a little translucent so they sit back from the
    /// body text. 1 is fully opaque.
    static let titleOpacity: CGFloat = 0.6

    /// The selected block's outline (editor card and sidebar row) is drawn at
    /// this fraction of the accent colour, so selection is clear but quiet.
    static let selectionOutlineOpacity: CGFloat = 0.5

    /// Space under a block's body text, inside the card, so the text doesn't
    /// sit on the card's bottom edge.
    static let bodyBottomPadding: CGFloat = 16

    // Each surface token comes in two forms: `Theme.x(theme)`, for views that
    // read `\.kishoEditorTheme` from the environment (so they redraw when the
    // theme changes), and the plain `Theme.x`, which reads the stored choice.

    /// Hairline for outlines and dividers.
    static func hairline(_ theme: EditorTheme) -> Color {
        theme == .sepia ? Color(red: 0.66, green: 0.58, blue: 0.46).opacity(0.40) : Color(platformColor: separator)
    }
    static var hairline: Color { hairline(.current) }

    /// Card face: the text background, so cards sit flush with the editor.
    static func cardBackground(_ theme: EditorTheme) -> Color {
        theme == .sepia ? Color(red: 0.992, green: 0.978, blue: 0.940) : Color(platformColor: textBackground)
    }
    static var cardBackground: Color { cardBackground(.current) }

    /// Editor canvas behind the cards: a step away from the card face so the
    /// outlines have something to sit against in both appearances.
    static func canvas(_ theme: EditorTheme) -> Color {
        theme == .sepia ? Color(red: 0.962, green: 0.940, blue: 0.884) : Color(platformColor: windowBackground)
    }
    static var canvas: Color { canvas(.current) }

    /// Sidebar and inspector surface. Sepia gets a slightly deeper paper than
    /// the canvas so the three areas read as separate; otherwise the system's.
    static func panel(_ theme: EditorTheme) -> Color {
        theme == .sepia ? Color(red: 0.944, green: 0.912, blue: 0.850) : Color(platformColor: windowBackground)
    }

    /// Text-entry fields in the panels (synopsis, notes): the card face.
    static func field(_ theme: EditorTheme) -> Color { cardBackground(theme) }

    /// Text view background for the card body (the AppKit/UIKit side of
    /// `cardBackground`, for the native text view).
    static var cardBackgroundPlatformColor: PlatformColor {
        EditorTheme.current == .sepia ? PlatformColor(red: 0.992, green: 0.978, blue: 0.940, alpha: 1) : textBackground
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


// MARK: - Accent

extension Theme {
    /// The colour for block selection, drop targets and focus rings, replacing
    /// the system blue so it belongs to the theme: slate on light surfaces,
    /// warm stone on dark ones, umber on Sepia. "Match System" follows
    /// whichever appearance the system is in.
    static func accent(_ theme: EditorTheme, scheme: ColorScheme) -> Color {
        if theme == .sepia { return Color(red: 0.58, green: 0.36, blue: 0.17) }        // umber
        switch theme.colorScheme ?? scheme {
        case .dark: return Color(red: 0.84, green: 0.82, blue: 0.76)                    // warm stone
        default:    return Color(red: 0.27, green: 0.32, blue: 0.37)                    // slate
        }
    }
}

/// The current theme's accent as a view property. Reads the stored theme and
/// the colour scheme itself, so any view redraws when either changes.
@propertyWrapper
struct ThemeAccent: DynamicProperty {
    @ThemeSetting private var theme
    @Environment(\.colorScheme) private var scheme
    var wrappedValue: Color { Theme.accent(theme, scheme: scheme) }
}

/// Tints the controls inside (pickers, buttons, toggles) with the theme's accent.
struct ThemedAccent: ViewModifier {
    @ThemeAccent private var accent
    func body(content: Content) -> some View { content.tint(accent) }
}

extension View {
    func themedAccent() -> some View { modifier(ThemedAccent()) }
}
