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

            // Bold Button
            Button(action: {
                binding.wrappedValue.isBold.toggle()
            }) {
                Image(systemName: "bold")
            }
            .foregroundStyle(binding.isBold.wrappedValue ? Color.accentColor : .primary)
            .help("Bold")
            .keyboardShortcut("b", modifiers: .command)

            // Italic Button
            Button(action: {
                binding.wrappedValue.isItalic.toggle()
            }) {
                Image(systemName: "italic")
            }
            .foregroundStyle(binding.isItalic.wrappedValue ? Color.accentColor : .primary)
            .help("Italic")
            .keyboardShortcut("i", modifiers: .command)
        }
        .onAppear {
            fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
        }
    }

}
