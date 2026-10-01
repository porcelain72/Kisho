//
//  Platform.swift
//  Kisho
//
//  The handful of AppKit/UIKit types the model and exporters need, under
//  one name per platform, plus the font-trait and colour helpers that
//  differ between the two. Everything else in the model is Foundation.
//

import SwiftUI

#if canImport(AppKit)
import AppKit

typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
typealias PlatformEdgeInsets = NSEdgeInsets

extension NSColor {
    /// The appearance-adaptive text colour, under UIKit's name so call
    /// sites read the same on both platforms.
    static var label: NSColor { .labelColor }
}

#elseif canImport(UIKit)
import UIKit

typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
typealias PlatformEdgeInsets = UIEdgeInsets

#endif

// MARK: - Fonts

extension PlatformFont {
    /// A font of `family` at `size`; the system font when the family is the
    /// system font's internal name or is not installed.
    static func kisho(family: String, size: CGFloat) -> PlatformFont {
        if family.hasPrefix(".") { return PlatformFont.systemFont(ofSize: size) }
        #if canImport(AppKit)
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
        #else
        let descriptor = UIFontDescriptor(fontAttributes: [.family: family])
        // UIFont(descriptor:) silently falls back to the system font for an
        // unknown family, which is the behaviour we want.
        return UIFont(descriptor: descriptor, size: size)
        #endif
    }

    /// Whether the font carries the bold trait.
    var isBoldTrait: Bool {
        #if canImport(AppKit)
        return NSFontManager.shared.traits(of: self).contains(.boldFontMask)
        #else
        return fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }

    /// Whether the font carries the italic trait.
    var isItalicTrait: Bool {
        #if canImport(AppKit)
        return NSFontManager.shared.traits(of: self).contains(.italicFontMask)
        #else
        return fontDescriptor.symbolicTraits.contains(.traitItalic)
        #endif
    }

    /// This font with the bold and/or italic trait added. A family without
    /// the face keeps the font it has (AppKit) or is left unchanged (UIKit).
    func addingTraits(bold: Bool, italic: Bool) -> PlatformFont {
        var font = self
        #if canImport(AppKit)
        let manager = NSFontManager.shared
        if bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        #else
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: font.pointSize)
        }
        #endif
        return font
    }

    /// This font with the bold and/or italic trait removed.
    func removingTraits(bold: Bool, italic: Bool) -> PlatformFont {
        var font = self
        #if canImport(AppKit)
        let manager = NSFontManager.shared
        if bold { font = manager.convert(font, toNotHaveTrait: .boldFontMask) }
        if italic { font = manager.convert(font, toNotHaveTrait: .italicFontMask) }
        #else
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.remove(.traitBold) }
        if italic { traits.remove(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: font.pointSize)
        }
        #endif
        return font
    }

    /// Family names installed on this device, for the font picker and tests.
    static var availableFamilyNames: [String] {
        #if canImport(AppKit)
        return NSFontManager.shared.availableFontFamilies
        #else
        return UIFont.familyNames
        #endif
    }
}

// MARK: - Colours

extension PlatformColor {
    /// sRGB components in 0…1, or nil for a colour that has none (patterns).
    var srgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        #if canImport(AppKit)
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b, a)
        #endif
    }
}

extension Color {
    /// A SwiftUI colour from the platform colour, by whichever initialiser
    /// the platform has.
    init(platformColor: PlatformColor) {
        #if canImport(AppKit)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}
