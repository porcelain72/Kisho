//
//  ToolbarTypographyControlsView.swift
//  Kisho
//
//  Created by Peter Macdonald on 23/07/2025.
//
import SwiftUI
import AppKit

struct ToolbarTypographyControlsView: View {
    var body: some View {
        // Bold / Italic / Underline apply to the selected text (or the caret) in
        // the focused block; the shortcuts live in the Format menu. The
        // document's font and size are in the inspector's Document section.
        HStack(spacing: 8) {
            Button(action: { SelectionFormatting.toggle(.bold) }) {
                Image(systemName: "bold")
            }
            .help("Bold (⌘B)")

            Button(action: { SelectionFormatting.toggle(.italic) }) {
                Image(systemName: "italic")
            }
            .help("Italic (⌘I)")

            Button(action: { SelectionFormatting.toggle(.underline) }) {
                Image(systemName: "underline")
            }
            .help("Underline (⌘U)")
        }
    }
}
