//
//  TypographySettings.swift
//  Kisho
//
//  Created by Peter Macdonald on 23/07/2025.
//

import SwiftUI

struct TypographySettings: Equatable, Codable {
    var fontFamily: String
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var color: Color

    enum CodingKeys: String, CodingKey {
        case fontFamily
        case fontSize
        case isBold
        case isItalic
        case colorHex
    }

    /// Default body font for new documents: a real, pickable family that reads
    /// as a writing face and ships on every Mac (and Windows, for exports).
    static let defaultFontFamily = "Georgia"
    static let defaultFontSize: Double = 14

    /// Display name for the picker: the system font's internal family name
    /// (".AppleSystemUIFont") is not something a user would recognise.
    static func displayName(forFamily family: String) -> String {
        family.hasPrefix(".") ? "System Font" : family
    }

    init(
        fontFamily: String = TypographySettings.defaultFontFamily,
        fontSize: Double = TypographySettings.defaultFontSize,
        isBold: Bool = false,
        isItalic: Bool = false,
        color: Color = .primary
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        fontFamily = try container.decode(String.self, forKey: .fontFamily)
        fontSize = try container.decode(Double.self, forKey: .fontSize)
        isBold = try container.decode(Bool.self, forKey: .isBold)
        isItalic = try container.decode(Bool.self, forKey: .isItalic)

        let hex = try container.decode(String.self, forKey: .colorHex)
        self.color = Color(hex: hex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(isBold, forKey: .isBold)
        try container.encode(isItalic, forKey: .isItalic)

        try container.encode(color.toHexString(), forKey: .colorHex)
    }
}


#if os(macOS)
extension TypographySettings {
    /// The document's body font: family and size only. Bold/italic are
    /// per-selection attributes, not document settings.
    var baseFont: NSFont {
        if fontFamily.hasPrefix(".") {
            return NSFont.systemFont(ofSize: CGFloat(fontSize))
        }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: fontFamily])
        return NSFont(descriptor: descriptor, size: CGFloat(fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
    }
}
#endif

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var hexNumber: UInt64 = 0
        let r, g, b: Double

        if scanner.scanHexInt64(&hexNumber) {
            r = Double((hexNumber & 0xFF0000) >> 16) / 255
            g = Double((hexNumber & 0x00FF00) >> 8) / 255
            b = Double(hexNumber & 0x0000FF) / 255
            self = Color(red: r, green: g, blue: b)
        } else {
            self = .primary // fallback
        }
    }

    func toHexString() -> String {
        #if os(macOS)
        let nsColor = NSColor(self)
        #else
        let uiColor = UIColor(self)
        let nsColor = NSColor(cgColor: uiColor.cgColor) ?? .black
        #endif

        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "000000" }

        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)

        return String(format: "%02X%02X%02X", r, g, b)
    }
}
