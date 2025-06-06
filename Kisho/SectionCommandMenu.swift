//
//  SectionCommandMenu.swift
//  Kisho
//
//  Created by Peter Macdonald on 04/06/2025.
//

import SwiftUI

struct SectionMenuCommands: Commands {
    // Grab the document model from the environment
    @EnvironmentObject private var document: KishoDocumentModel

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            // Add Sibling Section
            Button("Add Sibling Section") {
                document.addSiblingSection()
            }
            .keyboardShortcut(".", modifiers: .command)
            //.disabled(document.selectedSection == nil)

            // Add Child Section
            Button("Add Child Section") {
                document.addChildSection()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(document.selectedSection == nil)

            Divider()

            // Delete Section
            Button("Delete Section") {
              //  document.deleteSection()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(document.selectedSection == nil)
        }
    }
}
