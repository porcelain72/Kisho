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

    /// Hairline for outlines and dividers.
    static var hairline: Color {
        EditorTheme.current == .sepia ? Color(red: 0.62, green: 0.54, blue: 0.42).opacity(0.45) : Color(platformColor: separator)
    }

    /// Card face: the text background, so cards sit flush with the editor.
    static var cardBackground: Color {
        EditorTheme.current == .sepia ? Color(red: 0.985, green: 0.962, blue: 0.905) : Color(platformColor: textBackground)
    }

    /// Editor canvas behind the cards: a step away from the card face so the
    /// outlines have something to sit against in both appearances.
    static var canvas: Color {
        EditorTheme.current == .sepia ? Color(red: 0.945, green: 0.912, blue: 0.838) : Color(platformColor: windowBackground)
    }

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
