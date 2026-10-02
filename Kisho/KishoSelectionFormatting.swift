//
//  KishoSelectionFormatting.swift
//  Kisho
//
//  Bold/italic/underline on attributed text, shared by the Mac and iOS card
//  editors. Bold and italic are font traits; underline is a separate
//  attribute, which RTF, retypesetting and the exporters all carry. The
//  parts that need a live text view (which view has focus, toggling the
//  selection) live beside each platform's editor.
//

import Foundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum SelectionFormatting {
    enum Trait { case bold, italic, underline }

    /// Whether a run with these attributes carries the trait.
    static func attributes(_ attrs: [NSAttributedString.Key: Any], have trait: Trait) -> Bool {
        switch trait {
        case .underline:
            return ((attrs[.underlineStyle] as? Int) ?? 0) != 0
        case .bold:
            return (attrs[.font] as? PlatformFont)?.isBoldTrait ?? false
        case .italic:
            return (attrs[.font] as? PlatformFont)?.isItalicTrait ?? false
        }
    }

    /// `attrs` with the trait turned on or off.
    static func attributes(_ attrs: [NSAttributedString.Key: Any], setting trait: Trait, to on: Bool) -> [NSAttributedString.Key: Any] {
        var result = attrs
        switch trait {
        case .underline:
            if on { result[.underlineStyle] = NSUnderlineStyle.single.rawValue } else { result.removeValue(forKey: .underlineStyle) }
        case .bold, .italic:
            let font = (attrs[.font] as? PlatformFont) ?? PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
            let bold = trait == .bold, italic = trait == .italic
            result[.font] = on ? font.addingTraits(bold: bold, italic: italic)
                               : font.removingTraits(bold: bold, italic: italic)
        }
        return result
    }

    /// Toggles the trait over `range` of `storage`: if every run already has
    /// it, it is removed; otherwise it is added to every run. Returns whether
    /// the trait is now on.
    @discardableResult
    static func toggle(_ trait: Trait, in storage: NSMutableAttributedString, range: NSRange) -> Bool {
        var allHave = true
        storage.enumerateAttributes(in: range) { attrs, _, _ in
            if !attributes(attrs, have: trait) { allHave = false }
        }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attrs, runRange, _ in
            let updated = attributes(attrs, setting: trait, to: !allHave)
            if trait == .underline {
                if let style = updated[.underlineStyle] {
                    storage.addAttribute(.underlineStyle, value: style, range: runRange)
                } else {
                    storage.removeAttribute(.underlineStyle, range: runRange)
                }
            } else if let font = updated[.font] {
                storage.addAttribute(.font, value: font, range: runRange)
            }
        }
        storage.endEditing()
        return !allHave
    }

    /// `base` (family/size) carrying the bold/italic traits of `other`.
    static func font(_ base: PlatformFont, matchingTraitsOf other: PlatformFont) -> PlatformFont {
        base.addingTraits(bold: other.isBoldTrait, italic: other.isItalicTrait)
    }
}
