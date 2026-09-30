//
//  ToolbarTypographyControlsView.swift
//  Kisho
//
//  Created by Peter Macdonald on 23/07/2025.
//
import SwiftUI
import AppKit

struct ToolbarTypographyControlsView: View {
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager

    @State private var fontFamilies: [String] = []

    var body: some View {
        // Every change goes through the model so it is applied once and is
        // undoable (settings and fonts together).
        let binding = Binding<TypographySettings>(
            get: { document.typography },
            set: { document.setTypography($0, undoManager: undoManager) }
        )

        HStack(spacing: 8) {
            // Font Family Picker
            Picker("", selection: binding.fontFamily) {
                ForEach(fontFamilies, id: \.self) { family in
                    Text(family)
                        .font(.custom(family, size: 13))
                                    .tag(family)                }
            }
            .frame(width: 140)
            .labelsHidden()
            .help("Font Family")

            // Font Size Picker with Chevrons
            FontSizePicker(fontSize: binding.fontSize) { }

            // Bold / Italic apply to the selected text (or the caret) in the
            // focused block, like any text editor.
            Button(action: { SelectionFormatting.toggle(.bold) }) {
                Image(systemName: "bold")
            }
            .help("Bold (⌘B)")
            .keyboardShortcut("b", modifiers: .command)

            Button(action: { SelectionFormatting.toggle(.italic) }) {
                Image(systemName: "italic")
            }
            .help("Italic (⌘I)")
            .keyboardShortcut("i", modifiers: .command)
        }
        .onAppear {
            var families = NSFontManager.shared.availableFontFamilies.sorted()
            // The system font's family name (".AppleSystemUIFont") is not in the
            // list; keep the current choice selectable rather than showing blank.
            if !families.contains(document.typography.fontFamily) {
                families.insert(document.typography.fontFamily, at: 0)
            }
            fontFamilies = families
        }
    }

}
