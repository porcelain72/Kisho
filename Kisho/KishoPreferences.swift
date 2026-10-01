//
//  KishoPreferences.swift
//  Kisho
//
//  App-wide preferences (Kisho ▸ Settings…). Document-specific choices such
//  as the font live in the document; these are the defaults for new
//  documents and a few editing habits.
//

import SwiftUI

enum KishoPreferences {
    enum Key {
        static let defaultFontFamily = "defaultFontFamily"
        static let defaultFontSize = "defaultFontSize"
        static let newBlockFocusesBody = "newBlockFocusesBody"
        static let hasShownWelcome = "hasShownWelcome"
        static let printMargins = "printMargins"
        static let showInspector = "showInspector"
        static let showSynopses = "showSynopsesInSidebar"
    }

    private static var defaults: UserDefaults { .standard }

    /// Typography for a new document.
    static var defaultTypography: TypographySettings {
        let family = defaults.string(forKey: Key.defaultFontFamily) ?? TypographySettings.defaultFontFamily
        let size = defaults.object(forKey: Key.defaultFontSize) as? Double ?? TypographySettings.defaultFontSize
        return TypographySettings(fontFamily: family, fontSize: size)
    }

    /// Page margins for Print and PDF export. The system Page Setup sheet
    /// covers paper and orientation only, so this lives here.
    enum PrintMargins: String, CaseIterable, Identifiable {
        case narrow, normal, wide
        var id: String { rawValue }
        var title: String {
            switch self {
            case .narrow: return "Narrow (1.3 cm)"
            case .normal: return "Normal (2.5 cm)"
            case .wide: return "Wide (3.5 cm)"
            }
        }
        /// Points on every side.
        var points: CGFloat {
            switch self {
            case .narrow: return 36
            case .normal: return 72
            case .wide: return 100
            }
        }
    }

    static var printMargins: PrintMargins {
        PrintMargins(rawValue: defaults.string(forKey: Key.printMargins) ?? "") ?? .normal
    }

    /// Where the keyboard goes when a block is added: its title (default) or
    /// straight into its body.
    static var newBlockFocus: EditorFocusRequest.Field {
        defaults.bool(forKey: Key.newBlockFocusesBody) ? .body : .title
    }
}

#if os(macOS)
import AppKit

/// Kisho ▸ Settings…
struct KishoSettingsView: View {
    @AppStorage(KishoPreferences.Key.defaultFontFamily) private var fontFamily = TypographySettings.defaultFontFamily
    @AppStorage(KishoPreferences.Key.defaultFontSize) private var fontSize = TypographySettings.defaultFontSize
    @AppStorage(KishoPreferences.Key.newBlockFocusesBody) private var newBlockFocusesBody = false
    @AppStorage(KishoPreferences.Key.printMargins) private var printMargins = KishoPreferences.PrintMargins.normal.rawValue

    @State private var families: [String] = []

    private let sizes: [Double] = [10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24]

    var body: some View {
        Form {
            Section("New documents") {
                Picker("Font:", selection: $fontFamily) {
                    ForEach(families, id: \.self) { family in
                        Text(TypographySettings.displayName(forFamily: family)).tag(family)
                    }
                }
                Picker("Size:", selection: $fontSize) {
                    ForEach(sizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                Text("Existing documents keep their own font; change it from the toolbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Editing") {
                Picker("New blocks start in:", selection: $newBlockFocusesBody) {
                    Text("Title").tag(false)
                    Text("Body").tag(true)
                }
                .pickerStyle(.radioGroup)
                Text("Applies to Add Sibling (⌘=), Add Child (⇧⌘=) and ⌘↩.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Print and PDF") {
                Picker("Margins:", selection: $printMargins) {
                    ForEach(KishoPreferences.PrintMargins.allCases) { margins in
                        Text(margins.title).tag(margins.rawValue)
                    }
                }
                Text("Paper size and orientation come from File ▸ Page Setup….")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            var list = NSFontManager.shared.availableFontFamilies.sorted()
            if !list.contains(fontFamily) { list.insert(fontFamily, at: 0) }
            families = list
            if !sizes.contains(fontSize) { fontSize = TypographySettings.defaultFontSize }
        }
    }
}
#endif
